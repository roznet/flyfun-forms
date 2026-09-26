package aero.flyfun.forms.logic

import java.time.LocalDate

/** A stored person, as far as a scan decision is concerned. */
data class ScanPerson(
    val id: String,
    val firstName: String,
    val lastName: String,
    val dateOfBirth: LocalDate? = null,
    val sex: String? = null,
)

/** A stored, live document: whose it is and its number. */
data class ScanDocument(val id: String, val personId: String, val docNumber: String)

/** Where the scan was started from. */
sealed interface ScanContext {
    /** From a person's editor: the document is for them, unless the names say otherwise. */
    data class ForPerson(val personId: String) : ScanContext

    /** From a document's editor: fill that document in. */
    data class ForDocument(val documentId: String, val personId: String) : ScanContext

    /** From the People list: whose document it is is the question. */
    data object Standalone : ScanContext
}

/** What a scan means for the stored data, shown to the pilot before anything is written. */
data class ScanDecision(
    val result: MRZScanResult,
    val context: ScanContext,
    /** A live document with the same number, on anyone. */
    val duplicate: ScanDocument? = null,
    /** The scanned name is not the context person's. */
    val namesMismatch: Boolean = false,
    /** For a standalone scan: people whose names are close, best first, at most five. */
    val matchingPeople: List<String> = emptyList(),
)

/** The person's own fields after a scan, from [MRZResultProcessor.fillPerson]. */
data class PersonFill(
    val firstName: String,
    val lastName: String,
    val dateOfBirth: LocalDate?,
    val sex: String?,
)

/**
 * Port of `Services/MRZResultProcessor.swift`: what to do with a scanned
 * passport or ID card. Over plain values so the rules are tested on the JVM;
 * the app applies the pilot's choice.
 *
 * Nationality is not filled: on Android it derives from the document's issuing
 * country, never from the person.
 */
object MRZResultProcessor {

    fun process(
        result: MRZScanResult,
        context: ScanContext,
        people: List<ScanPerson>,
        documents: List<ScanDocument>,
    ): ScanDecision {
        val excluding = (context as? ScanContext.ForDocument)?.documentId
        val duplicate = findDuplicateDocument(result.passportNumber, documents, excluding)
        val byId = people.associateBy { it.id }
        return when (context) {
            is ScanContext.ForDocument -> ScanDecision(
                result, context, duplicate,
                namesMismatch = byId[context.personId]?.let { !namesMatch(it.firstName, it.lastName, result) } ?: false,
            )
            is ScanContext.ForPerson -> ScanDecision(
                result, context, duplicate,
                namesMismatch = byId[context.personId]?.let {
                    it.firstName.isNotEmpty() && !namesMatch(it.firstName, it.lastName, result)
                } ?: false,
            )
            ScanContext.Standalone -> ScanDecision(
                result, context, duplicate,
                matchingPeople = findMatchingPeople(result, people),
            )
        }
    }

    /**
     * The person's fields with the scan filled into the empty ones. A name the
     * pilot typed is kept unless [overwriteName]: an MRZ is transliterated and
     * upper-cased, and may be truncated.
     */
    fun fillPerson(person: ScanPerson, result: MRZScanResult, overwriteName: Boolean = false) = PersonFill(
        firstName = if (person.firstName.isEmpty() || overwriteName) result.givenNames else person.firstName,
        lastName = if (person.lastName.isEmpty() || overwriteName) result.surname else person.lastName,
        dateOfBirth = person.dateOfBirth ?: result.dateOfBirth,
        sex = person.sex?.takeIf { it.isNotEmpty() } ?: when (result.gender) {
            "M" -> "Male"
            "F" -> "Female"
            else -> null
        },
    )

    /** The document type the scan's format means, in the editor's vocabulary. */
    fun docType(result: MRZScanResult): String =
        if (result.format == MRZFormat.TD1) "Identity card" else "Passport"

    /**
     * Same person, ignoring case and hyphens (the MRZ writes them as spaces),
     * or same surname with one first name a prefix of the other, of at least
     * two letters (the MRZ truncates long names).
     */
    fun namesMatch(firstName: String, lastName: String, result: MRZScanResult): Boolean {
        fun norm(s: String) = s.lowercase().replace("-", " ").trim()
        val personFirst = norm(firstName)
        val personLast = norm(lastName)
        val scanFirst = norm(result.givenNames)
        val scanLast = norm(result.surname)

        if (personLast == scanLast && personFirst == scanFirst) return true
        if (personLast == scanLast) {
            val shorter = minOf(personFirst.length, scanFirst.length)
            if (shorter >= 2 && personFirst.take(shorter) == scanFirst.take(shorter)) return true
        }
        return false
    }

    /** 0.0 to 1.0: surname weighs most, then first name, and a matching birth date adds a little. */
    fun nameSimilarity(person: ScanPerson, result: MRZScanResult): Double {
        val personLast = person.lastName.lowercase().trim()
        val scanLast = result.surname.lowercase().trim()
        val personFirst = person.firstName.lowercase().trim()
        val scanFirst = result.givenNames.lowercase().trim()
        if (personLast.isEmpty()) return 0.0

        var score = 0.0
        if (personLast == scanLast) {
            score += 0.5
        } else if (personLast.startsWith(scanLast) || scanLast.startsWith(personLast)) {
            score += 0.3
        }
        if (personFirst == scanFirst) {
            score += 0.4
        } else if (personFirst.isNotEmpty() && scanFirst.isNotEmpty()) {
            val shorter = minOf(personFirst.length, scanFirst.length)
            if (shorter >= 2 && personFirst.take(shorter) == scanFirst.take(shorter)) score += 0.2
        }
        if (person.dateOfBirth == result.dateOfBirth) score += 0.1
        return minOf(score, 1.0)
    }

    /** A document with this number held by anyone, other than [excludingId]. */
    fun findDuplicateDocument(number: String, documents: List<ScanDocument>, excludingId: String? = null): ScanDocument? {
        if (number.isEmpty()) return null
        return documents.firstOrNull { it.docNumber == number && it.id != excludingId }
    }

    /** People whose names are close to the scan's, best first, at most five. */
    fun findMatchingPeople(result: MRZScanResult, people: List<ScanPerson>): List<String> {
        if (result.surname.isEmpty()) return emptyList()
        return people
            .map { it to nameSimilarity(it, result) }
            .filter { it.second >= 0.4 }
            .sortedByDescending { it.second }
            .take(5)
            .map { it.first.id }
    }
}
