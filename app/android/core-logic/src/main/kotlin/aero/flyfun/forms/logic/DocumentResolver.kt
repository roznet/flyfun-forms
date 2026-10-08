package aero.flyfun.forms.logic

import java.time.LocalDate

/**
 * A travel document, reduced to what resolution actually needs.
 *
 * Deliberately not the Room entity: `:core-logic` stays Android-free, so the
 * app layer maps its entities onto this.
 */
data class ResolvableDocument(
    val id: String,
    val docType: String = "Passport",
    val docNumber: String = "",
    val issuingCountry: String? = null,
    val expiryDate: LocalDate? = null,
    val isActive: Boolean = true,
)

/**
 * Selects the best [ResolvableDocument] for a person given a target airport.
 *
 * Port of `Services/DocumentResolver.swift`. Resolution order:
 *  0. Active filter - inactive documents are never considered
 *  1. The document chosen by hand for this flight (`chosenDocNumbers`)
 *  2. Region match - prefer a document issued by a country in the airport's region
 *  3. Tiebreak by latest expiry
 *  4. Fallback to the whole set by latest expiry
 *
 * The flight's choices are passed in rather than read from storage, because
 * this module has no Android dependencies. The app layer supplies them.
 */
object DocumentResolver {

    /** Same regions as iOS `Services/AirportRegion.swift`; change both together. */
    private enum class Region { SCHENGEN, UK, EU_NON_SCHENGEN, OTHER }

    /** Airports whose territory is outside the region of their country prefix. */
    private val exactRegions: Map<String, Region> = mapOf(
        "ENSB" to Region.OTHER, // Svalbard: Norwegian, but outside Schengen
        "EKVG" to Region.OTHER, // Faroe Islands: Danish, but outside Schengen and the EU
    )

    /** ICAO prefix to region. */
    private val prefixRegions: Map<String, Region> = mapOf(
        // Schengen
        "LF" to Region.SCHENGEN, // France
        "LS" to Region.SCHENGEN, // Switzerland (Schengen associate)
        "ED" to Region.SCHENGEN, // Germany
        "ET" to Region.SCHENGEN, // Germany (military)
        "EB" to Region.SCHENGEN, // Belgium
        "EH" to Region.SCHENGEN, // Netherlands
        "EL" to Region.SCHENGEN, // Luxembourg
        "LE" to Region.SCHENGEN, // Spain
        "GC" to Region.SCHENGEN, // Canary Islands (Spain)
        "LI" to Region.SCHENGEN, // Italy
        "LP" to Region.SCHENGEN, // Portugal (incl. Azores, Madeira)
        "LO" to Region.SCHENGEN, // Austria
        "LG" to Region.SCHENGEN, // Greece
        "LK" to Region.SCHENGEN, // Czech Republic
        "LZ" to Region.SCHENGEN, // Slovakia
        "EP" to Region.SCHENGEN, // Poland
        "LH" to Region.SCHENGEN, // Hungary
        "LJ" to Region.SCHENGEN, // Slovenia
        "EV" to Region.SCHENGEN, // Latvia
        "EY" to Region.SCHENGEN, // Lithuania
        "EE" to Region.SCHENGEN, // Estonia
        "LM" to Region.SCHENGEN, // Malta
        "BI" to Region.SCHENGEN, // Iceland (Schengen associate)
        "EN" to Region.SCHENGEN, // Norway (Schengen associate)
        "EF" to Region.SCHENGEN, // Finland
        "ES" to Region.SCHENGEN, // Sweden
        "EK" to Region.SCHENGEN, // Denmark
        "LR" to Region.SCHENGEN, // Romania
        "LB" to Region.SCHENGEN, // Bulgaria
        "LD" to Region.SCHENGEN, // Croatia
        // EU, not Schengen
        "EI" to Region.EU_NON_SCHENGEN, // Ireland
        "LC" to Region.EU_NON_SCHENGEN, // Cyprus
        // UK (incl. Channel Islands and Isle of Man); Gibraltar (LX) falls to OTHER
        "EG" to Region.UK,
    )

    private fun region(airport: String): Region {
        val code = airport.trim().uppercase()
        return exactRegions[code] ?: prefixRegions[code.take(2)] ?: Region.OTHER
    }

    /** ISO alpha-3 codes for EU/Schengen issuing countries. */
    private val schengenCountries: Set<String> = setOf(
        "FRA", "DEU", "BEL", "NLD", "ESP", "ITA", "PRT", "AUT", "LUX",
        "CHE", "GRC", "CZE", "POL", "HUN", "SVN", "LVA", "LTU", "EST",
        "MLT", "ISL", "NOR", "FIN", "SWE", "DNK", "ROU", "BGR", "HRV",
        "CYP", "SVK", "IRL", "LIE",
    )

    /**
     * @param documents every document held for the person, active or not
     * @param airport target airport ICAO; an exact override, else its two-letter prefix, sets the region
     * @param chosenDocNumbers the documents picked by hand for the flight
     *   (iOS `Flight.chosenDocNumbers`); one of this person's active documents
     *   in that set wins over the automatic choice
     */
    fun resolve(
        documents: List<ResolvableDocument>,
        airport: String,
        chosenDocNumbers: Collection<String> = emptyList(),
    ): ResolvableDocument? {
        val docs = documents.filter { it.isActive }
        if (docs.isEmpty()) return null
        // Matches Swift: a single active document short-circuits before the
        // flight's choice is consulted.
        if (docs.size == 1) return docs[0]

        chosen(docs, chosenDocNumbers)?.let { return it }

        // EU members outside Schengen prefer the same documents as Schengen.
        val regionMatches = when (region(airport)) {
            Region.SCHENGEN, Region.EU_NON_SCHENGEN -> docs.filter { schengenCountries.contains(it.issuingCountry ?: "") }
            Region.UK -> docs.filter { it.issuingCountry == "GBR" }
            Region.OTHER -> emptyList()
        }

        val candidates = regionMatches.ifEmpty { docs }
        // A missing expiry sorts last, matching Swift's `.distantPast` default.
        return candidates.maxByOrNull { it.expiryDate ?: LocalDate.MIN }
    }

    /**
     * The person's active document picked by hand for the flight, if any.
     *
     * Keyed by document number, as on iOS: unlike a row id it is the same on
     * every device the flight travels to.
     */
    fun chosen(documents: List<ResolvableDocument>, chosenDocNumbers: Collection<String>): ResolvableDocument? {
        if (chosenDocNumbers.isEmpty()) return null
        return documents.firstOrNull { it.isActive && it.docNumber.isNotEmpty() && it.docNumber in chosenDocNumbers }
    }

    /**
     * [chosenDocNumbers] with this person's choice set to [document], or
     * cleared back to automatic when [document] is null. Other people's
     * choices on the same flight are kept.
     */
    fun choosing(
        document: ResolvableDocument?,
        personDocuments: List<ResolvableDocument>,
        chosenDocNumbers: List<String>,
    ): List<String> {
        val personNumbers = personDocuments.map { it.docNumber }.toSet()
        val result = chosenDocNumbers.filterNot { it in personNumbers }.toMutableList()
        if (document != null && document.docNumber.isNotEmpty()) result += document.docNumber
        return result
    }
}
