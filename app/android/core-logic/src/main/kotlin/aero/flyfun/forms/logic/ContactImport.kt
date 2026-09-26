package aero.flyfun.forms.logic

import java.time.LocalDate

/** A contact picked from the address book, reduced to what a person can use. */
data class ImportedContact(
    val firstName: String,
    val lastName: String,
    val phones: List<String> = emptyList(),
    val emails: List<String> = emptyList(),
    val addresses: List<String> = emptyList(),
    val dateOfBirth: LocalDate? = null,
)

/** The person fields a contact can fill. */
data class ContactFields(
    val firstName: String,
    val lastName: String,
    val phone: String?,
    val email: String?,
    val address: String?,
    val dateOfBirth: LocalDate?,
)

/**
 * Port of iOS `ContactResolveView`'s matching and merging: find the people a
 * picked contact may already be, and fold the contact into one of them.
 */
object ContactImport {

    /** A stored person, as far as matching a contact is concerned. */
    data class Candidate(val id: String, val firstName: String, val lastName: String)

    /**
     * People the contact may be: same last name with the first name the same
     * or sharing its first three letters either way, or both names within two
     * edits. Exact matches first, then by last name.
     */
    fun matches(contact: ImportedContact, people: List<Candidate>): List<String> {
        val first = contact.firstName.lowercase()
        val last = contact.lastName.lowercase()
        if (first.isEmpty() && last.isEmpty()) return emptyList()
        return people.filter { person ->
            val pFirst = person.firstName.lowercase()
            val pLast = person.lastName.lowercase()
            val sameLast = pLast == last &&
                (pFirst == first || pFirst.startsWith(first.take(3)) || first.startsWith(pFirst.take(3)))
            val close = last.isNotEmpty() && pLast.isNotEmpty() &&
                levenshtein(pLast, last) <= 2 && levenshtein(pFirst, first) <= 2
            sameLast || close
        }.sortedWith(
            compareByDescending<Candidate> { it.lastName.lowercase() == last && it.firstName.lowercase() == first }
                .thenBy { it.lastName },
        ).map { it.id }
    }

    /**
     * The person after merging the contact into them, with the phone, e-mail
     * and address the pilot picked from the contact's. "Fill Missing Only"
     * ([override] false) touches only empty fields; "Override All" takes the
     * contact's name and every value it has.
     */
    fun merge(
        person: ContactFields,
        contact: ImportedContact,
        phone: String?,
        email: String?,
        address: String?,
        override: Boolean,
    ): ContactFields {
        fun String?.present() = this?.takeIf { it.isNotBlank() }
        return if (override) {
            ContactFields(
                firstName = contact.firstName,
                lastName = contact.lastName,
                phone = phone.present() ?: person.phone,
                email = email.present() ?: person.email,
                address = address.present() ?: person.address,
                dateOfBirth = contact.dateOfBirth ?: person.dateOfBirth,
            )
        } else {
            person.copy(
                phone = person.phone.present() ?: phone.present(),
                email = person.email.present() ?: email.present(),
                address = person.address.present() ?: address.present(),
                dateOfBirth = person.dateOfBirth ?: contact.dateOfBirth,
            )
        }
    }

    fun levenshtein(a: String, b: String): Int {
        var previous = IntArray(b.length + 1) { it }
        for (i in 1..a.length) {
            val current = IntArray(b.length + 1)
            current[0] = i
            for (j in 1..b.length) {
                val cost = if (a[i - 1] == b[j - 1]) 0 else 1
                current[j] = minOf(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[b.length]
    }

    /**
     * A postal address as one line: street, city, postcode, country, as iOS
     * builds it from `CNPostalAddress`; blank parts are left out.
     */
    fun addressLine(street: String?, city: String?, postcode: String?, country: String?): String? =
        listOf(street, city, postcode, country)
            .mapNotNull { it?.trim()?.replace('\n', ' ')?.takeIf(String::isNotEmpty) }
            .joinToString(", ")
            .ifEmpty { null }

    /**
     * An Android contact birthday: `YYYY-MM-DD`, or `--MM-DD` with no year,
     * which is no use as a date of birth.
     */
    fun parseBirthday(value: String?): LocalDate? =
        value?.trim()?.takeIf { !it.startsWith("--") }?.let { runCatching { LocalDate.parse(it.take(10)) }.getOrNull() }
}
