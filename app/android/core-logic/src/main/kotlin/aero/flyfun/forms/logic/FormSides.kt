package aero.flyfun.forms.logic

/**
 * Which ends of a flight get a forms section, and which forms each one shows.
 *
 * Port of `FlightEditView.formSection` / `hasForms`. A local flight (origin =
 * destination) has two sections for the one airport: its arrival forms and its
 * departure forms are different paperwork, and folding them into one section
 * lost the departure side entirely.
 */
object FormSides {

    const val ARRIVAL = "arrival"
    const val DEPARTURE = "departure"

    data class Side(val icao: String, val direction: String)

    /** Arrival first, then departure, as on iOS. Blank or partial ICAO codes are skipped. */
    fun of(origin: String, destination: String): List<Side> = listOfNotNull(
        destination.normalisedIcao()?.let { Side(it, ARRIVAL) },
        origin.normalisedIcao()?.let { Side(it, DEPARTURE) },
    )

    /**
     * The forms one side shows.
     *
     * Only web forms (book-out, PPR) are filtered by direction; a form with no
     * direction applies to either side. Document forms always show: iOS does
     * not filter them, and a customs form tagged "arrival" at the origin is
     * still the one the pilot may need to file for a local flight.
     */
    fun <T> applicable(
        forms: List<T>,
        direction: String,
        isWeb: (T) -> Boolean,
        directionOf: (T) -> String?,
    ): List<T> = forms.filter { !isWeb(it) || (directionOf(it) ?: direction) == direction }

    /** One side's forms in the order they are offered. */
    data class Grouped<T>(val primary: T?, val web: List<T>, val others: List<T>)

    /**
     * The primary form - the server lists the one to file first, e.g. the
     * customs notice the AIP names - then the airport's web forms, then any
     * other document forms, which the screen folds away. Port of iOS
     * `formSection`.
     */
    fun <T> group(forms: List<T>, isWeb: (T) -> Boolean): Grouped<T> {
        val documents = forms.filterNot(isWeb)
        return Grouped(primary = documents.firstOrNull(), web = forms.filter(isWeb), others = documents.drop(1))
    }

    private fun String.normalisedIcao(): String? = trim().uppercase().takeIf { it.length == 4 }
}
