package aero.flyfun.forms.logic

import java.time.Instant

/** A person, as far as ordering and suggesting them is concerned. */
data class RankedPerson(
    val id: String,
    val firstName: String,
    val lastName: String,
    val isUsualCrew: Boolean = false,
    /** Most recent departure of a flight they were on, crew or passenger. */
    val lastFlight: Instant? = null,
)

/** Who was on one flight. */
data class FlightPeople(
    val flightId: String,
    val departure: Instant,
    val aircraftId: String? = null,
    val crew: List<String> = emptyList(),
    val passengers: List<String> = emptyList(),
) {
    val everyone: List<String> get() = crew + passengers
}

/**
 * Search, order and group people the way the iOS People tab and people picker
 * do (`PeopleListView.swift`, `PeoplePickerView.swift`, `Person.coTravelers`).
 * Over ids and plain values so it is tested on the JVM.
 */
object PeopleRanking {

    /** Case-insensitive substring of the first or last name; a blank query matches everyone. */
    fun matches(query: String, firstName: String, lastName: String): Boolean {
        val needle = query.trim().lowercase()
        if (needle.isEmpty()) return true
        return firstName.lowercase().contains(needle) || lastName.lowercase().contains(needle) ||
            "$firstName $lastName".lowercase().contains(needle)
    }

    /** The People tab's "Sort by Recent": last flown first, never flown last, then by name. */
    fun byRecent(people: List<RankedPerson>): List<RankedPerson> =
        people.sortedWith(
            compareByDescending<RankedPerson> { it.lastFlight ?: Instant.MIN }
                .thenBy(String.CASE_INSENSITIVE_ORDER) { it.lastName }
                .thenBy(String.CASE_INSENSITIVE_ORDER) { it.firstName },
        )

    /** The picker's order: usual crew first, then last flown, then by last name. */
    fun forPicker(people: List<RankedPerson>): List<RankedPerson> =
        people.sortedWith(
            compareByDescending<RankedPerson> { it.isUsualCrew }
                .thenByDescending { it.lastFlight ?: Instant.MIN }
                .thenBy(String.CASE_INSENSITIVE_ORDER) { it.lastName }
                .thenBy(String.CASE_INSENSITIVE_ORDER) { it.firstName },
        )

    /**
     * Everyone who has flown with [anchorId] at least [minimumFlights] times,
     * most often first. Port of `Person.coTravelers(minimumFlights:)`.
     */
    fun coTravelers(anchorId: String, flights: List<FlightPeople>, minimumFlights: Int = 2): List<String> {
        val counts = linkedMapOf<String, Int>()
        flights.filter { anchorId in it.everyone }.forEach { flight ->
            flight.everyone.distinct().filter { it != anchorId }.forEach { counts[it] = (counts[it] ?: 0) + 1 }
        }
        return counts.entries
            .filter { it.value >= minimumFlights }
            .sortedByDescending { it.value }
            .map { it.key }
    }

    /**
     * "Smith" is a last name; "Jane van Dijk" is Jane + van Dijk. Port of
     * `PeoplePickerView.splitName`, for adding the person a search did not find.
     */
    fun splitName(name: String): Pair<String, String> {
        val words = name.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (words.size <= 1) return "" to name.trim()
        return words[0] to words.drop(1).joinToString(" ")
    }

    /**
     * Crew and passengers with each person once: someone listed in both
     * stays crew. One person cannot be both on the same flight.
     */
    fun withoutDuplicates(crew: List<String>, passengers: List<String>): Pair<List<String>, List<String>> {
        val crewSet = crew.distinct()
        return crewSet to passengers.distinct().filterNot { it in crewSet }
    }
}
