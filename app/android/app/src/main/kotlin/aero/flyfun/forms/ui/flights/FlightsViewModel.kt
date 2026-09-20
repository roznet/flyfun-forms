package aero.flyfun.forms.ui.flights

import aero.flyfun.forms.data.AircraftEntity
import aero.flyfun.forms.data.FlightEntity
import aero.flyfun.forms.data.FlightRepository
import aero.flyfun.forms.data.FormRequestBuilder
import aero.flyfun.forms.data.PeopleRepository
import aero.flyfun.forms.data.PersonEntity
import aero.flyfun.forms.net.ApiClient
import aero.flyfun.forms.net.FillPlan
import aero.flyfun.forms.net.FormInfo
import aero.flyfun.forms.net.ServerValidationError
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.io.File

/** What the flight detail screen needs, loaded together. */
data class FlightDetail(
    val flight: FlightEntity,
    val aircraft: AircraftEntity? = null,
    val crew: List<PersonEntity> = emptyList(),
    val passengers: List<PersonEntity> = emptyList(),
)

/** Forms available at one end of the flight. */
data class AirportForms(
    val icao: String,
    val name: String = "",
    val direction: String? = null,
    val forms: List<FormInfo> = emptyList(),
    val error: String? = null,
)

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

    private val _airportForms = MutableStateFlow<List<AirportForms>>(emptyList())
    val airportForms: StateFlow<List<AirportForms>> = _airportForms.asStateFlow()

    private val _generate = MutableStateFlow<GenerateState>(GenerateState.Idle)
    val generate: StateFlow<GenerateState> = _generate.asStateFlow()

    fun load(flightId: String) = viewModelScope.launch {
        val flight = flights.flight(flightId) ?: return@launch
        _detail.value = FlightDetail(
            flight = flight,
            aircraft = flight.aircraftId?.let { flights.aircraft(it) },
            crew = flights.crew(flightId),
            passengers = flights.passengers(flightId),
        )
        loadForms(flight)
    }

    fun save(flight: FlightEntity) = viewModelScope.launch {
        flights.saveFlight(flight)
        load(flight.id)
    }

    fun delete(id: String) = viewModelScope.launch { flights.deleteFlight(id) }

    fun setCrew(flightId: String, ids: List<String>) = viewModelScope.launch {
        flights.setCrew(flightId, ids); load(flightId)
    }

    fun setPassengers(flightId: String, ids: List<String>) = viewModelScope.launch {
        flights.setPassengers(flightId, ids); load(flightId)
    }

    suspend fun newFlightDefaults(): AircraftEntity? = flights.suggestedAircraft()

    /**
     * Forms for both ends of the route.
     *
     * Both are queried because a trip usually needs paperwork at each end - a
     * departure form where you leave and a customs form where you arrive - and
     * the pilot should see both without editing the flight to find out.
     */
    private fun loadForms(flight: FlightEntity) = viewModelScope.launch {
        val ends = listOf(flight.originICAO, flight.destinationICAO)
            .map { it.trim().uppercase() }
            .filter { it.length == 4 }
            .distinct()

        _airportForms.value = ends.map { icao ->
            runCatching { api.forms.airport(icao) }.fold(
                onSuccess = { detail ->
                    val direction = FormRequestBuilder.directionFor(icao, flight)
                    AirportForms(
                        icao = icao,
                        name = detail.name,
                        direction = direction,
                        // A form tagged for one side only is noise on the other.
                        forms = detail.forms.filter { it.direction == null || it.direction == direction },
                    )
                },
                onFailure = { AirportForms(icao = icao, error = it.friendlyMessage()) },
            )
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
                            val file = File(cacheDir, "forms").apply { mkdirs() }.resolve(name)
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
