package aero.flyfun.forms.logic

import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/** A flight reduced to what leg matching needs; the app maps its entities onto this. */
data class Leg(
    val id: String,
    val origin: String,
    val destination: String,
    val departure: Instant,
    val arrival: Instant,
)

/**
 * Finds the other flights a form asks about. Port of the connecting- and
 * return-flight lookups in iOS `FlightEditView.buildRequest`.
 *
 * Legs are matched by time and airport alone, with no trip linkage required:
 * pilots rarely group legs into trips, and the forms only care what flew
 * through the airport either side of this one.
 */
object FlightLegs {

    /** How far either side of this flight a related leg may be. */
    val WINDOW: Duration = Duration.ofDays(14)

    /**
     * The leg connecting with [current] at [airport].
     *
     * Arriving there, it is the next flight departing from it; leaving from
     * there, it is the previous flight that landed there. A local flight
     * counts as arriving, as on iOS.
     */
    fun connecting(current: Leg, airport: String, all: List<Leg>): Leg? {
        val icao = airport.icao()
        val nearby = all
            .filter { it.id != current.id && Duration.between(current.departure, it.departure).abs() < WINDOW }
            .sortedBy { it.departure }
        return if (icao == current.destination.icao()) {
            nearby.firstOrNull { it.departure >= current.departure && it.origin.icao() == icao }
        } else {
            nearby.lastOrNull { it.departure <= current.departure && it.destination.icao() == icao }
        }
    }

    /**
     * For forms that ask when you will be back (book-outs): the first later
     * flight landing at [airport] again, however many legs away. Only asked
     * of the departure airport. A local flight is its own return.
     */
    fun returning(current: Leg, airport: String, all: List<Leg>): Leg? {
        val icao = airport.icao()
        if (icao != current.origin.icao()) return null
        if (current.destination.icao() == icao) return current
        return all
            .filter {
                it.id != current.id &&
                    it.departure > current.departure &&
                    Duration.between(current.departure, it.departure) < WINDOW &&
                    it.destination.icao() == icao
            }
            .minByOrNull { it.departure }
    }

    /**
     * Where the arrival goes when the departure moves from [oldDeparture] to
     * [newDeparture]. Port of iOS `autoSyncArrivalDate`.
     *
     * The arrival day follows the departure day only while the pilot has not
     * moved it off that day themselves, and only the day moves: a leg landing
     * at 21:30 stays at 21:30. Compared in UTC, the day it is filed under.
     */
    fun arrivalFollowing(oldDeparture: Instant, newDeparture: Instant, arrival: Instant): Instant {
        if (arrival.utcDay() != oldDeparture.utcDay()) return arrival
        return alignUtcDay(arrival, newDeparture)
    }

    /** [instant]'s UTC time of day on [reference]'s UTC day. Port of `Flight.alignUTCDay`. */
    fun alignUtcDay(instant: Instant, reference: Instant): Instant {
        val time = instant.atOffset(ZoneOffset.UTC).toLocalTime().withSecond(0).withNano(0)
        return reference.utcDay().atTime(time).toInstant(ZoneOffset.UTC)
    }

    private fun Instant.utcDay(): LocalDate = atOffset(ZoneOffset.UTC).toLocalDate()

    private fun String.icao() = trim().uppercase()
}
