package aero.flyfun.forms.ui.flights

import aero.flyfun.forms.data.AircraftEntity
import aero.flyfun.forms.data.FlightEntity
import aero.flyfun.forms.data.FlightRepository
import aero.flyfun.forms.data.FormFiles
import aero.flyfun.forms.data.FormRequestBuilder
import aero.flyfun.forms.data.PeopleRepository
import aero.flyfun.forms.data.PersonEntity
import aero.flyfun.forms.logic.FlightLegs
import aero.flyfun.forms.logic.FormSides
import aero.flyfun.forms.logic.Leg
import aero.flyfun.forms.net.ExtraFieldValue
import aero.flyfun.forms.net.GenerateRequest
import aero.flyfun.forms.net.ApiClient
import aero.flyfun.forms.net.FillPlan
import aero.flyfun.forms.net.FormInfo
import aero.flyfun.forms.net.ServerValidationError
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.File
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * The flight being edited, with who and what is on it.
 *
 * This is a draft: every edit lands here and nothing reaches the database until
 * [FlightsViewModel.save]. Schedule and aircraft used to save on the spot while
 * route and observations waited for Save, so Back kept half an edit.
 */
data class FlightDetail(
    val flight: FlightEntity,
    val aircraft: AircraftEntity? = null,
    val crew: List<PersonEntity> = emptyList(),
    val passengers: List<PersonEntity> = emptyList(),
    /** Named as the contact on forms; their phone and e-mail fill form fields. */
    val responsiblePerson: PersonEntity? = null,
    /** Not stored yet: + opens a draft, and only Save creates the row. */
    val isNew: Boolean = false,
)

/** Forms for one side of the flight. A local flight has two, for the one airport. */
data class AirportForms(
    val icao: String,
    val direction: String,
    val name: String = "",
    val forms: List<FormInfo> = emptyList(),
    val loading: Boolean = false,
    val error: String? = null,
)

/** One airport's forms as fetched, shared by both sides of a local flight. */
private sealed interface FetchedForms {
    data object Loading : FetchedForms
    data class Loaded(val name: String, val forms: List<FormInfo>) : FetchedForms
    data class Failed(val message: String) : FetchedForms
}

sealed interface GenerateState {
    data object Idle : GenerateState
    data class Working(val formId: String) : GenerateState
    data class Ready(val file: File, val label: String) : GenerateState
    data class Invalid(val errors: List<ServerValidationError>) : GenerateState
    data class Failed(val message: String) : GenerateState

    /** A web form's prefill plan, ready to open in a WebView. */
    data class WebPlan(val plan: FillPlan) : GenerateState
}

class FlightsViewModel(
    private val flights: FlightRepository,
    private val people: PeopleRepository,
    private val api: ApiClient,
    private val cacheDir: File,
) : ViewModel() {

    val allFlights: StateFlow<List<FlightEntity>> =
        flights.observeFlights()
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val aircraft: StateFlow<List<AircraftEntity>> =
        flights.observeAircraft()
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    private val _detail = MutableStateFlow<FlightDetail?>(null)
    val detail: StateFlow<FlightDetail?> = _detail.asStateFlow()

    /** The draft as last loaded or saved; the draft differs from it when there is something to lose. */
    private val baseline = MutableStateFlow<FlightDetail?>(null)

    val hasUnsavedChanges: StateFlow<Boolean> =
        combine(_detail, baseline) { draft, saved -> draft != null && draft != saved }
            .stateIn(viewModelScope, SharingStarted.Eagerly, false)

    private val fetched = MutableStateFlow<Map<String, FetchedForms>>(emptyMap())

    val airportForms: StateFlow<List<AirportForms>> =
        combine(_detail, fetched) { draft, byIcao ->
            val flight = draft?.flight ?: return@combine emptyList<AirportForms>()
            FormSides.of(flight.originICAO, flight.destinationICAO).map { side ->
                when (val result = byIcao[side.icao]) {
                    is FetchedForms.Loaded -> AirportForms(
                        icao = side.icao,
                        direction = side.direction,
                        name = result.name,
                        forms = FormSides.applicable(result.forms, side.direction, { it.isWebForm }, { it.direction }),
                    )
                    is FetchedForms.Failed -> AirportForms(side.icao, side.direction, error = result.message)
                    FetchedForms.Loading, null -> AirportForms(side.icao, side.direction, loading = true)
                }
            }
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    private val _generate = MutableStateFlow<GenerateState>(GenerateState.Idle)
    val generate: StateFlow<GenerateState> = _generate.asStateFlow()

    private var opened = false

    /**
     * Open a stored flight, or a new draft for [NEW_FLIGHT].
     *
     * Once per ViewModel: the screen calls this on every composition of its
     * route, including after rotation, and must not throw away the draft.
     */
    fun open(flightId: String) {
        if (opened) return
        opened = true
        viewModelScope.launch {
            val detail = if (flightId == NEW_FLIGHT) newDraft() else loadStored(flightId) ?: return@launch
            show(detail)
        }
    }

    private suspend fun loadStored(flightId: String): FlightDetail? {
        val flight = flights.flight(flightId) ?: return null
        return FlightDetail(
            flight = flight,
            aircraft = flight.aircraftId?.let { flights.aircraft(it) },
            crew = flights.crew(flightId),
            passengers = flights.passengers(flightId),
            responsiblePerson = flight.responsiblePersonId?.let { people.person(it)?.person },
        )
    }

    private suspend fun newDraft(): FlightDetail {
        val suggested = flights.suggestedAircraft()
        val departure = Instant.now().truncatedTo(ChronoUnit.HOURS).plus(1, ChronoUnit.DAYS)
        return FlightDetail(
            flight = FlightEntity(
                departureInstant = departure,
                arrivalInstant = departure.plus(2, ChronoUnit.HOURS),
                aircraftId = suggested?.id,
                // Seed the route from where the aircraft usually lives.
                originICAO = suggested?.usualBase.orEmpty(),
            ),
            aircraft = suggested,
            isNew = true,
        )
    }

    /**
     * Make [detail] the draft. It is compared against itself, so nothing is
     * unsaved yet - unless [unsaved], for a leg the pilot just asked for,
     * which Back should not drop without asking.
     */
    private fun show(detail: FlightDetail, unsaved: Boolean = false) {
        _detail.value = detail
        baseline.value = if (unsaved) null else detail
        _extraValues.value = emptyMap()
        fetchForms(detail.flight)
    }

    /** Apply an edit to the draft. Nothing is stored until [save]. */
    fun edit(transform: (FlightDetail) -> FlightDetail) {
        val before = _detail.value ?: return
        val after = transform(before)
        _detail.value = after
        if (after.flight.originICAO != before.flight.originICAO ||
            after.flight.destinationICAO != before.flight.destinationICAO
        ) {
            fetchForms(after.flight)
        }
    }

    fun editFlight(transform: (FlightEntity) -> FlightEntity) = edit { it.copy(flight = transform(it.flight)) }

    /** Moving the departure carries an arrival on the same day along with it. */
    fun setDeparture(departure: Instant) = editFlight {
        it.copy(
            departureInstant = departure,
            arrivalInstant = FlightLegs.arrivalFollowing(it.departureInstant, departure, it.arrivalInstant),
        )
    }

    fun setAircraft(aircraftId: String?) = edit { detail ->
        detail.copy(
            flight = detail.flight.copy(aircraftId = aircraftId),
            aircraft = aircraft.value.firstOrNull { it.id == aircraftId },
        )
    }

    fun setCrew(crew: List<PersonEntity>) = edit { it.copy(crew = crew) }

    fun setPassengers(passengers: List<PersonEntity>) = edit { it.copy(passengers = passengers) }

    /** Also keeps `contact` in step, as iOS `setResponsiblePerson` does for older builds reading it. */
    fun setResponsiblePerson(person: PersonEntity?) = edit {
        it.copy(
            flight = it.flight.copy(responsiblePersonId = person?.id, contact = person?.phone),
            responsiblePerson = person,
        )
    }

    private val _extraValues = MutableStateFlow<Map<String, Map<String, ExtraFieldValue>>>(emptyMap())

    /**
     * What was entered in each form's own extra fields, by [formKey]. Held for
     * the screen only, as on iOS: they are per form and rarely reused.
     */
    val extraValues: StateFlow<Map<String, Map<String, ExtraFieldValue>>> = _extraValues.asStateFlow()

    fun setExtra(airport: String, formId: String, key: String, value: ExtraFieldValue?) {
        val formKey = formKey(airport, formId)
        _extraValues.update { all ->
            val current = all[formKey].orEmpty()
            all + (formKey to if (value == null) current - key else current + (key to value))
        }
    }

    /** Store the draft: the flight row, then who is on it. */
    fun save(): Job = viewModelScope.launch {
        val draft = _detail.value ?: return@launch
        val id = draft.flight.id
        flights.saveFlight(draft.flight)
        flights.setCrew(id, draft.crew.map { it.id })
        flights.setPassengers(id, draft.passengers.map { it.id })
        val stored = draft.copy(isNew = false)
        // Only if nothing was edited while this ran; a later edit stays unsaved.
        if (_detail.compareAndSet(draft, stored)) baseline.value = stored
    }

    fun delete(id: String) = viewModelScope.launch { flights.deleteFlight(id) }

    /** The way back: the route reversed, leaving when this flight lands. */
    fun createReturnFlight() = createLeg { from, leg ->
        leg.copy(
            originICAO = from.destinationICAO,
            destinationICAO = from.originICAO,
            departureInstant = from.arrivalInstant,
            arrivalInstant = from.arrivalInstant,
        )
    }

    /** On from where this flight lands, in the same trip; the destination is left to fill in. */
    fun createNextLeg() = createLeg { from, leg ->
        leg.copy(
            originICAO = from.destinationICAO,
            departureInstant = from.arrivalInstant,
            arrivalInstant = from.arrivalInstant,
            tripId = from.tripId,
            legOrder = from.legOrder + 1,
        )
    }

    fun duplicateFlight() = createLeg { from, leg ->
        leg.copy(
            originICAO = from.originICAO,
            destinationICAO = from.destinationICAO,
            departureInstant = from.departureInstant,
            arrivalInstant = from.arrivalInstant,
            observations = from.observations,
        )
    }

    /**
     * Store this flight, then open a new leg made from it. Port of iOS
     * `createReturnFlight` / `createNextLeg` / `duplicateFlight`: the aircraft,
     * people, nature, reason and responsible person carry over (`copyCommon`),
     * and [shape] sets the route and schedule from the flight it came [from].
     *
     * The new leg is a draft like any other, shown as unsaved: iOS inserts it
     * at once, and here Save stores it.
     */
    private fun createLeg(shape: (from: FlightEntity, leg: FlightEntity) -> FlightEntity) = viewModelScope.launch {
        save().join()
        val current = _detail.value ?: return@launch
        val from = current.flight
        val common = FlightEntity(
            departureInstant = from.departureInstant,
            arrivalInstant = from.arrivalInstant,
            aircraftId = from.aircraftId,
            nature = from.nature,
            contact = from.contact,
            reasonForVisit = from.reasonForVisit,
            responsiblePersonId = from.responsiblePersonId,
        )
        show(current.copy(flight = shape(from, common), isNew = true), unsaved = true)
    }

    /**
     * Forms for both ends of the route.
     *
     * Both are queried because a trip usually needs paperwork at each end - a
     * departure form where you leave and a customs form where you arrive - and
     * the pilot should see both without editing the flight to find out. An
     * airport that failed (offline, signed out) is tried again on the next
     * route change or open.
     */
    private fun fetchForms(flight: FlightEntity) {
        FormSides.of(flight.originICAO, flight.destinationICAO)
            .map { it.icao }
            .distinct()
            .filter { icao ->
                val known = fetched.value[icao]
                known == null || known is FetchedForms.Failed
            }
            .forEach { icao ->
                fetched.update { it + (icao to FetchedForms.Loading) }
                viewModelScope.launch {
                    val result: FetchedForms = runCatching { api.forms.airport(icao) }.fold(
                        onSuccess = { FetchedForms.Loaded(it.name, it.forms) },
                        onFailure = { FetchedForms.Failed(it.friendlyMessage()) },
                    )
                    fetched.update { it + (icao to result) }
                }
            }
    }

    /**
     * Everything a form is generated from, built from the draft - so what is
     * on screen is what gets filled, saved or not. Null, with the state set to
     * say why, when the form cannot be asked for yet.
     */
    private suspend fun buildRequest(airport: String, form: FormInfo): GenerateRequest? {
        val current = _detail.value ?: return null
        val aircraft = current.aircraft
        if (aircraft == null) {
            _generate.value = GenerateState.Failed("Pick an aircraft for this flight first.")
            return null
        }
        _generate.value = GenerateState.Working(form.id)

        // Resolve each person's document once, against this airport.
        val documents = (current.crew + current.passengers).associate { person ->
            person.id to people.resolveDocument(person.id, airport)
        }

        val entered = _extraValues.value[formKey(airport, form.id)].orEmpty()
        val extras = FormRequestBuilder.extraFields(
            entered = FormRequestBuilder.withChoiceDefaults(form.extraFields, entered),
            reasonForVisit = current.flight.reasonForVisit,
            responsiblePerson = current.responsiblePerson,
        )

        // Other legs as stored; this one as drafted.
        val stored = flights.observeFlights().first().filter { it.id != current.flight.id }
        val legs = stored.map { it.toLeg() }
        val thisLeg = current.flight.toLeg()

        val connecting = if (form.hasConnectingFlight) {
            FlightLegs.connecting(thisLeg, airport, legs)
                ?.let { leg -> stored.first { it.id == leg.id } }
                ?.let { leg -> leg to leg.responsiblePersonId?.let { people.person(it)?.person?.displayName } }
        } else {
            null
        }

        val returning = if (form.hasReturnFlight == true) {
            FlightLegs.returning(thisLeg, airport, legs)?.let { leg ->
                if (leg.id == current.flight.id) {
                    FormRequestBuilder.returnFlightPayload(current.flight, current.crew.size + current.passengers.size)
                } else {
                    val back = stored.first { it.id == leg.id }
                    FormRequestBuilder.returnFlightPayload(
                        back,
                        flights.crew(back.id).size + flights.passengers(back.id).size,
                    )
                }
            }
        } else {
            null
        }

        return FormRequestBuilder.build(
            airport = airport,
            formId = form.id,
            flight = current.flight,
            aircraft = aircraft,
            crew = current.crew,
            passengers = current.passengers,
            documentFor = { documents[it.id] },
            responsiblePerson = current.responsiblePerson,
            extraFields = extras,
            connectingFlight = connecting,
            returnFlight = returning,
        )
    }

    fun generateForm(airport: String, form: FormInfo) = viewModelScope.launch {
        val request = buildRequest(airport, form) ?: return@launch
        _generate.value = runCatching { api.forms.generate(request) }.fold(
            onSuccess = { response ->
                when {
                    response.isSuccessful -> {
                        val bytes = response.body()?.bytes()
                        if (bytes == null) {
                            GenerateState.Failed("The server returned an empty file.")
                        } else {
                            val name = response.suggestedFileName(airport, form.id)
                            val file = FormFiles.dir(cacheDir).resolve(name)
                            file.writeBytes(bytes)
                            GenerateState.Ready(file, form.label)
                        }
                    }
                    response.code() == 422 -> {
                        val body = response.errorBody()?.string().orEmpty()
                        GenerateState.Invalid(api.parseValidationErrors(body))
                    }
                    else -> GenerateState.Failed("Server returned ${response.code()}.")
                }
            },
            onFailure = { GenerateState.Failed(it.friendlyMessage()) },
        )
    }

    /**
     * Web forms are the airport's own page, so the server returns a plan of
     * values to type into it rather than a file. Same request body as
     * /generate - only the endpoint and what comes back differ.
     */
    fun prefillWebForm(airport: String, form: FormInfo) = viewModelScope.launch {
        val request = buildRequest(airport, form) ?: return@launch
        _generate.value = runCatching { api.forms.prefill(request) }.fold(
            onSuccess = { GenerateState.WebPlan(it) },
            onFailure = { GenerateState.Failed(it.friendlyMessage()) },
        )
    }

    fun clearGenerateState() { _generate.value = GenerateState.Idle }

    companion object {
        /** Route argument for a flight that does not exist yet. */
        const val NEW_FLIGHT = "new"

        /** One form at one airport; a local flight's two sides share it, as on iOS. */
        fun formKey(airport: String, formId: String) = "${airport.uppercase()}_$formId"
    }
}

/**
 * A pilot at an airfield can act on "sign in" or "no connection". They cannot
 * act on "HTTP 401", which is what Retrofit hands us.
 */
private fun Throwable.friendlyMessage(): String = when {
    this is java.net.UnknownHostException ->
        "No connection. Loading forms needs the server."
    this is java.net.SocketTimeoutException ->
        "The server took too long to respond."
    this is retrofit2.HttpException -> when (code()) {
        401, 403 -> "Sign in to load the forms for this airport."
        404 -> "This airport has no forms on file."
        in 500..599 -> "The forms server is having trouble. Try again shortly."
        else -> "The server returned ${code()}."
    }
    this is java.io.IOException -> "Network problem: ${message ?: "connection failed"}"
    else -> message ?: this::class.simpleName.orEmpty()
}

/** Prefer the server's filename so the extension matches the real format. */
private fun retrofit2.Response<okhttp3.ResponseBody>.suggestedFileName(
    airport: String,
    formId: String,
): String {
    val disposition = headers()["Content-Disposition"].orEmpty()
    Regex("""filename\*?=(?:UTF-8'')?"?([^";]+)"?""").find(disposition)
        ?.groupValues?.getOrNull(1)
        ?.trim()
        ?.takeIf { it.isNotBlank() }
        ?.let { return it.substringAfterLast('/') }

    val extension = when (body()?.contentType()?.subtype?.lowercase()) {
        "pdf" -> "pdf"
        "vnd.openxmlformats-officedocument.wordprocessingml.document" -> "docx"
        "vnd.openxmlformats-officedocument.spreadsheetml.sheet" -> "xlsx"
        else -> "pdf"
    }
    return "$airport-$formId.$extension"
}

private fun FlightEntity.toLeg() = Leg(
    id = id,
    origin = originICAO,
    destination = destinationICAO,
    departure = departureInstant,
    arrival = arrivalInstant,
)
