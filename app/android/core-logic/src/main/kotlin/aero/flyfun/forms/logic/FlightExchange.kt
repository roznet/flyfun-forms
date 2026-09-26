package aero.flyfun.forms.logic

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneOffset

/**
 * The cross-app flight format the flyfun services exchange (rzflight
 * `designs/flight_exchange_design.md`; `FlightExchange` in euro_aip and
 * RZFlight). FlyFun Weather serves it at `GET /api/flights/{id}/export`.
 *
 * Only what forms uses is kept: the route's endpoints and times, and the
 * aircraft. It is PII-free by design, so there are never people in it.
 */
@Serializable
data class FlightExchange(
    @SerialName("schema_version") val schemaVersion: Int = CURRENT_SCHEMA_VERSION,
    val name: String? = null,
    val route: Route,
    val aircraft: Aircraft? = null,
    val source: Source? = null,
) {
    @Serializable
    data class Route(
        val departure: String = "",
        val destination: String = "",
        @SerialName("aircraft_type") val aircraftType: String? = null,
        @SerialName("departure_time") val departureTime: String? = null,
        @SerialName("arrival_time") val arrivalTime: String? = null,
    )

    @Serializable
    data class Aircraft(val registration: String? = null, val type: String? = null)

    @Serializable
    data class Source(
        val app: String? = null,
        @SerialName("flight_id") val flightId: String? = null,
    )

    companion object {
        const val CURRENT_SCHEMA_VERSION = 1

        private val json = Json { ignoreUnknownKeys = true }

        /**
         * Decode a payload, refusing a newer schema version than this build
         * knows: a v2 may change what fields mean, and reading it as v1 would
         * put a wrong route on a customs form.
         */
        fun decode(text: String): FlightExchange {
            val exchange = json.decodeFromString(serializer(), text)
            require(exchange.schemaVersion <= CURRENT_SCHEMA_VERSION) {
                "Unsupported flight format (version ${exchange.schemaVersion}). Update the app to import it."
            }
            return exchange
        }
    }
}

/** One of the pilot's FlyFun Weather flights, as `GET /api/flights` lists it (a subset of weather's `FlightResponse`). */
@Serializable
data class WeatherFlightSummary(
    val id: String,
    @SerialName("route_name") val routeName: String = "",
    val waypoints: List<String> = emptyList(),
    @SerialName("departure_time") val departureTime: String? = null,
) {
    /** "EGTK → LSGS" when the endpoints are known, else the flight's name. */
    val routeLabel: String
        get() = if (waypoints.size >= 2) "${waypoints.first()} → ${waypoints.last()}" else routeName

    val departure: Instant? get() = ExchangeTime.parse(departureTime)

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        /** Newest departure first, as iOS lists them; flights without a time last. */
        fun decodeList(text: String): List<WeatherFlightSummary> =
            json.decodeFromString<List<WeatherFlightSummary>>(text)
                .sortedWith(compareByDescending(nullsFirst<Instant>()) { it.departure })
    }
}

/** ISO 8601 times on the exchange wire. */
object ExchangeTime {
    /**
     * An instant from ISO 8601 with an offset or `Z`; a time with no offset is
     * read as UTC, which is how the flyfun servers store times (Python's
     * `isoformat()` of a naive UTC datetime drops the offset). Null for
     * anything unreadable: a missing time is better than a wrong one.
     */
    fun parse(text: String?): Instant? {
        val value = text?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        return runCatching { OffsetDateTime.parse(value).toInstant() }.getOrNull()
            ?: runCatching { LocalDateTime.parse(value).toInstant(ZoneOffset.UTC) }.getOrNull()
    }
}

/**
 * What an imported route puts on a new flight. Port of the route half of iOS
 * `NewFlightFlow.apply(_:)` over plain values.
 */
data class ImportedRoute(
    val origin: String,
    val destination: String,
    val departure: Instant,
    val arrival: Instant,
    /** Registration and type of the aircraft it names, or null. */
    val registration: String?,
    val aircraftType: String?,
) {
    companion object {
        /**
         * Apply [exchange] over the current route values.
         *
         * An empty endpoint keeps the current one: an empty departure is a gap
         * in the source, not an instruction to clear a good value. A departure
         * with no arrival moves the arrival onto the departure's UTC day, keeping
         * its time, as iOS does; the pilot then corrects the time, not the date.
         */
        fun from(
            exchange: FlightExchange,
            origin: String,
            destination: String,
            departure: Instant,
            arrival: Instant,
        ): ImportedRoute {
            val route = exchange.route
            val newDeparture = ExchangeTime.parse(route.departureTime)
            val newArrival = ExchangeTime.parse(route.arrivalTime)
            return ImportedRoute(
                origin = route.departure.trim().uppercase().ifEmpty { origin },
                destination = route.destination.trim().uppercase().ifEmpty { destination },
                departure = newDeparture ?: departure,
                arrival = newArrival ?: newDeparture?.let { alignUtcDay(arrival, it) } ?: arrival,
                registration = exchange.aircraft?.registration?.trim()?.ifEmpty { null },
                aircraftType = (exchange.aircraft?.type ?: route.aircraftType)?.trim()?.ifEmpty { null },
            )
        }

        /** [time]'s UTC time of day on [day]'s UTC date. Port of iOS `Flight.alignUTCDay`. */
        fun alignUtcDay(time: Instant, day: Instant): Instant {
            val clock = time.atOffset(ZoneOffset.UTC).toLocalTime()
            return day.atOffset(ZoneOffset.UTC).toLocalDate().atTime(clock).toInstant(ZoneOffset.UTC)
        }

        /** Registrations compared as iOS does: without dashes, any case. `G-ABCD` is `gabcd`. */
        fun sameRegistration(a: String, b: String): Boolean = normalise(a) == normalise(b)

        private fun normalise(registration: String) = registration.replace("-", "").trim().uppercase()
    }
}
