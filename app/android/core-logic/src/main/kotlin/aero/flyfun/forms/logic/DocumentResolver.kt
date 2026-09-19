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
 *  1. User override - a remembered choice for this person + airport prefix
 *  2. Region match - prefer a document issued by a country in the airport's region
 *  3. Tiebreak by latest expiry
 *  4. Fallback to the whole set by latest expiry
 *
 * The override is passed in rather than read from storage, because this module
 * has no Android dependencies. The app layer supplies it.
 */
object DocumentResolver {

    private enum class Region { SCHENGEN, UK, OTHER }

    /** ICAO prefix to region. */
    private val prefixRegions: Map<String, Region> = mapOf(
        // Schengen / EU
        "LF" to Region.SCHENGEN, // France
        "LS" to Region.SCHENGEN, // Switzerland (Schengen associate)
        "ED" to Region.SCHENGEN, // Germany
        "EB" to Region.SCHENGEN, // Belgium
        "EH" to Region.SCHENGEN, // Netherlands
        "LE" to Region.SCHENGEN, // Spain
        "LI" to Region.SCHENGEN, // Italy
        "LP" to Region.SCHENGEN, // Portugal
        "LO" to Region.SCHENGEN, // Austria
        "EL" to Region.SCHENGEN, // Greece (also LG)
        "LG" to Region.SCHENGEN, // Greece
        "LK" to Region.SCHENGEN, // Czech Republic
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
        "LC" to Region.SCHENGEN, // Cyprus
        // UK
        "EG" to Region.UK,
    )

    /** ISO alpha-3 codes for EU/Schengen issuing countries. */
    private val schengenCountries: Set<String> = setOf(
        "FRA", "DEU", "BEL", "NLD", "ESP", "ITA", "PRT", "AUT", "LUX",
        "CHE", "GRC", "CZE", "POL", "HUN", "SVN", "LVA", "LTU", "EST",
        "MLT", "ISL", "NOR", "FIN", "SWE", "DNK", "ROU", "BGR", "HRV",
        "CYP", "SVK", "IRL",
    )

    /**
     * @param documents every document held for the person, active or not
     * @param airport target airport ICAO; only the first two characters matter
     * @param overrideDocumentId a previously remembered choice for this person
     *   and airport prefix, if any
     */
    fun resolve(
        documents: List<ResolvableDocument>,
        airport: String,
        overrideDocumentId: String? = null,
    ): ResolvableDocument? {
        val docs = documents.filter { it.isActive }
        if (docs.isEmpty()) return null
        // Matches Swift: a single active document short-circuits before the
        // override is consulted.
        if (docs.size == 1) return docs[0]

        if (overrideDocumentId != null) {
            docs.firstOrNull { it.id == overrideDocumentId }?.let { return it }
        }

        val prefix = airport.take(2)
        val region = prefixRegions[prefix] ?: Region.OTHER

        val regionMatches = when (region) {
            Region.SCHENGEN -> docs.filter { schengenCountries.contains(it.issuingCountry ?: "") }
            Region.UK -> docs.filter { it.issuingCountry == "GBR" }
            Region.OTHER -> emptyList()
        }

        val candidates = regionMatches.ifEmpty { docs }
        // A missing expiry sorts last, matching Swift's `.distantPast` default.
        return candidates.maxByOrNull { it.expiryDate ?: LocalDate.MIN }
    }
}
