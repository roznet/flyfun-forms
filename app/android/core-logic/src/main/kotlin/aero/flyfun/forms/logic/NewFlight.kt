package aero.flyfun.forms.logic

import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * A one-tap suggestion for a new flight's people: who was on board last time.
 * Port of iOS `PeopleSuggestion`, over ids.
 */
data class PeopleSuggestion(
    val crew: List<String>,
    val passengers: List<String>,
    /** The flight it copies, or null for "Usual crew". */
    val fromFlightId: String?,
) {
    companion object {
        /**
         * The most specific evidence available: the latest flight in the same
         * aircraft, else the latest flight with anyone on board, else everyone
         * marked usual crew. Null on a first run.
         */
        fun suggest(flights: List<FlightPeople>, aircraftId: String?, usualCrew: List<String>): PeopleSuggestion? {
            val withPeople = flights.filter { it.everyone.isNotEmpty() }.sortedByDescending { it.departure }
            val match = aircraftId?.let { id -> withPeople.firstOrNull { it.aircraftId == id } } ?: withPeople.firstOrNull()
            if (match != null) return PeopleSuggestion(match.crew, match.passengers, match.flightId)
            if (usualCrew.isEmpty()) return null
            return PeopleSuggestion(usualCrew, emptyList(), null)
        }

        /**
         * The flights a crew can be copied from: those with anyone on board,
         * newest first, one per distinct set of people - the same four people
         * every weekend is one choice, not eight rows.
         */
        fun crewSources(flights: List<FlightPeople>): List<FlightPeople> =
            flights.filter { it.everyone.isNotEmpty() }
                .sortedByDescending { it.departure }
                .distinctBy { it.everyone.toSet() }

        /** "Anne, Bob and 2 more", for the suggestion's second line. */
        fun summary(names: List<String>): String = when (names.size) {
            0 -> ""
            1, 2 -> names.joinToString(", ")
            else -> "${names[0]}, ${names[1]} and ${names.size - 2} more"
        }
    }
}

/**
 * Repeating a previous flight. Port of iOS `Flight.nextOccurrence`.
 */
object NextOccurrence {
    /**
     * The flight's time of day, read in [zone] (the origin's, when known) or
     * UTC, on its next occurrence from [now]: today if still ahead, otherwise
     * tomorrow. The arrival keeps the leg's duration, so an overnight leg stays
     * overnight; an arrival before the departure (never entered) is clamped.
     */
    fun of(departure: Instant, arrival: Instant, now: Instant, zone: String? = null): Pair<Instant, Instant> {
        val z: ZoneId = zone?.let { runCatching { ZoneId.of(it) }.getOrNull() } ?: ZoneOffset.UTC
        val time = departure.atZone(z).toLocalTime().withSecond(0).withNano(0)
        val today = LocalDate.ofInstant(now, z)
        var next = today.atTime(time).atZone(z).toInstant()
        if (!next.isAfter(now)) next = today.plusDays(1).atTime(time).atZone(z).toInstant()
        val duration = Duration.between(departure, arrival).let { if (it.isNegative) Duration.ZERO else it }
        return next to next.plus(duration)
    }
}
