package aero.flyfun.forms.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/** Ported from `flyfun-formsTests/MRZResultProcessorTests.swift`, plus the decisions around it. */
class MRZResultProcessorTest {

    private fun scan(
        surname: String = "Doe",
        givenNames: String = "John",
        passportNumber: String = "AB1234567",
        dateOfBirth: LocalDate = LocalDate.of(1970, 1, 1),
        gender: String = "M",
        issuingCountry: String = "GBR",
        format: MRZFormat = MRZFormat.TD3,
    ) = MRZScanResult(
        surname = surname,
        givenNames = givenNames,
        passportNumber = passportNumber,
        nationality = issuingCountry,
        dateOfBirth = dateOfBirth,
        expiryDate = LocalDate.of(2035, 1, 1),
        gender = gender,
        issuingCountry = issuingCountry,
        format = format,
    )

    private fun person(first: String, last: String, id: String = "p-$last", dob: LocalDate? = null, sex: String? = null) =
        ScanPerson(id, first, last, dob, sex)

    // --- Name matching

    @Test fun `exact name match`() = assertTrue(MRZResultProcessor.namesMatch("John", "Doe", scan()))

    @Test fun `case insensitive name match`() = assertTrue(MRZResultProcessor.namesMatch("john", "doe", scan()))

    @Test fun `truncated first name match`() =
        assertTrue(MRZResultProcessor.namesMatch("Jean-Pierre", "Dupont", scan("Dupont", "Jean Pierre")))

    @Test fun `different surname does not match`() = assertFalse(MRZResultProcessor.namesMatch("John", "Smith", scan()))

    @Test fun `empty person name does not match`() = assertFalse(MRZResultProcessor.namesMatch("", "", scan()))

    // --- Similarity

    @Test fun `perfect match gives score at least 0_9`() =
        assertTrue(MRZResultProcessor.nameSimilarity(person("John", "Doe"), scan()) >= 0.9)

    @Test
    fun `surname-only match gives moderate score`() {
        val score = MRZResultProcessor.nameSimilarity(person("Jane", "Doe"), scan())
        assertTrue(score >= 0.4)
        assertTrue(score < 0.9)
    }

    @Test fun `no match gives low score`() =
        assertTrue(MRZResultProcessor.nameSimilarity(person("Alice", "Smith"), scan()) < 0.4)

    // --- Filling

    @Test
    fun `fillPerson sets empty fields`() {
        val fill = MRZResultProcessor.fillPerson(person("", ""), scan(gender = "F"))
        assertEquals("John", fill.firstName)
        assertEquals("Doe", fill.lastName)
        assertEquals("Female", fill.sex)
        assertEquals(LocalDate.of(1970, 1, 1), fill.dateOfBirth)
    }

    @Test
    fun `fillPerson does not overwrite existing fields by default`() {
        val fill = MRZResultProcessor.fillPerson(person("Jane", "Smith", sex = "Female"), scan(gender = "M"))
        assertEquals("Jane", fill.firstName)
        assertEquals("Smith", fill.lastName)
        assertEquals("Female", fill.sex)
    }

    @Test
    fun `fillPerson overwrites name when asked`() {
        val fill = MRZResultProcessor.fillPerson(person("Jane", "Smith"), scan(), overwriteName = true)
        assertEquals("John", fill.firstName)
        assertEquals("Doe", fill.lastName)
    }

    @Test
    fun `identity card for TD1, passport otherwise`() {
        assertEquals("Identity card", MRZResultProcessor.docType(scan(format = MRZFormat.TD1)))
        assertEquals("Passport", MRZResultProcessor.docType(scan()))
    }

    // --- Decisions

    @Test
    fun `duplicate is found on anyone, not just the context person`() {
        val docs = listOf(ScanDocument("d1", "someone-else", "AB1234567"))
        val decision = MRZResultProcessor.process(scan(), ScanContext.ForPerson("p-Doe"), listOf(person("John", "Doe")), docs)
        assertEquals("someone-else", decision.duplicate?.personId)
    }

    @Test
    fun `the document being filled is not its own duplicate`() {
        val docs = listOf(ScanDocument("d1", "p-Doe", "AB1234567"))
        val decision = MRZResultProcessor.process(
            scan(), ScanContext.ForDocument("d1", "p-Doe"), listOf(person("John", "Doe")), docs,
        )
        assertNull(decision.duplicate)
    }

    @Test
    fun `a person with no first name yet is not a mismatch`() {
        val decision = MRZResultProcessor.process(scan(), ScanContext.ForPerson("p-"), listOf(person("", "")), emptyList())
        assertFalse(decision.namesMismatch)
    }

    @Test
    fun `a different name on the person is a mismatch`() {
        val decision = MRZResultProcessor.process(
            scan(), ScanContext.ForPerson("p-Smith"), listOf(person("Jane", "Smith")), emptyList(),
        )
        assertTrue(decision.namesMismatch)
    }

    @Test
    fun `standalone scan lists close names, best first, and nobody unrelated`() {
        val people = listOf(
            person("Jane", "Doe", id = "jane"),
            person("John", "Doe", id = "john"),
            person("Alice", "Smith", id = "alice"),
        )
        val decision = MRZResultProcessor.process(scan(), ScanContext.Standalone, people, emptyList())
        assertEquals(listOf("john", "jane"), decision.matchingPeople)
        assertFalse(decision.namesMismatch)
    }
}
