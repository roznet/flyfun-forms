package aero.flyfun.forms.ui.flights

import aero.flyfun.forms.data.AircraftEntity
import aero.flyfun.forms.data.FlightEntity
import aero.flyfun.forms.data.FlightRepository
import aero.flyfun.forms.data.FormFiles
import aero.flyfun.forms.data.FormRequestBuilder
import aero.flyfun.forms.data.PeopleRepository
import aero.flyfun.forms.data.PersonEntity
import aero.flyfun.forms.logic.FormSides
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

    /** Make [detail] the draft and what it is compared against. */
    private fun show(detail: FlightDetail) {
        _detail.value = detail
        baseline.value = detail
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

    fun setAircraft(aircraftId: String?) = edit { detail ->
        detail.copy(
            flight = detail.flight.copy(aircraftId = aircraftId),
            aircraft = aircraft.value.firstOrNull { it.id == aircraftId },
        )
    }

    fun setCrew(crew: List<PersonEntity>) = edit { it.copy(crew = crew) }

    fun setPassengers(passengers: List<PersonEntity>) = edit { it.copy(passengers = passengers) }

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

    fun generateForm(airport: String, form: FormInfo) = viewModelScope.launch {
        val current = _detail.value ?: return@launch
        val aircraft = current.aircraft
        if (aircraft == null) {
            _generate.value = GenerateState.Failed("Pick an aircraft for this flight first.")
            return@launch
        }
        _generate.value = GenerateState.Working(form.id)

        // Resolve each person's document once, against this airport.
        val documents = (current.crew + current.passengers).associate { person ->
            person.id to people.resolveDocument(person.id, airport)
        }

        val request = FormRequestBuilder.build(
            airport = airport,
            formId = form.id,
            flight = current.flight,
            aircraft = aircraft,
            crew = current.crew,
            passengers = current.passengers,
            documentFor = { documents[it.id] },
        )

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
        val current = _detail.value ?: return@launch
        val aircraft = current.aircraft
        if (aircraft == null) {
            _generate.value = GenerateState.Failed("Pick an aircraft for this flight first.")
            return@launch
        }
        _generate.value = GenerateState.Working(form.id)

        val documents = (current.crew + current.passengers).associate { person ->
            person.id to people.resolveDocument(person.id, airport)
        }
        val request = FormRequestBuilder.build(
            airport = airport,
            formId = form.id,
            flight = current.flight,
            aircraft = aircraft,
            crew = current.crew,
            passengers = current.passengers,
            documentFor = { documents[it.id] },
        )
        _generate.value = runCatching { api.forms.prefill(request) }.fold(
            onSuccess = { GenerateState.WebPlan(it) },
            onFailure = { GenerateState.Failed(it.friendlyMessage()) },
        )
    }

    fun clearGenerateState() { _generate.value = GenerateState.Idle }

    companion object {
        /** Route argument for a flight that does not exist yet. */
        const val NEW_FLIGHT = "new"
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
