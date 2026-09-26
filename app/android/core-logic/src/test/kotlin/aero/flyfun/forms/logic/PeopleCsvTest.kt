package aero.flyfun.forms.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/** Ported from `flyfun-formsTests/PeopleCSVImporterTests.swift`. */
class PeopleCsvTest {

    private val fullHeader =
        "First Name,Last Name,Gender,DoB,Nationality,Doc Type,Doc Number,Doc Expiry,Doc Issuing State,Type"

    @Test
    fun `parses basic CSV with all columns`() {
        val csv = "$fullHeader\nAnna,Eriksson,F,1974-08-12,FRA,Passport,L898902C3,2031-06-30,FRA,Crew"
        val r = PeopleCsv.parse(csv)
        assertEquals(1, r.size)
        with(r[0]) {
            assertEquals("Anna", firstName)
            assertEquals("Eriksson", lastName)
            assertEquals("F", sex)
            assertEquals(LocalDate.of(1974, 8, 12), dateOfBirth)
            assertEquals("FRA", nationality)
            assertEquals("Passport", docType)
            assertEquals("L898902C3", docNumber)
            assertEquals(LocalDate.of(2031, 6, 30), docExpiry)
            assertEquals("FRA", docIssuingCountry)
            assertTrue(isCrew)
        }
    }

    @Test
    fun `handles missing optional columns gracefully`() {
        val r = PeopleCsv.parse("First Name,Last Name\nBo,Lindqvist")
        assertEquals(1, r.size)
        assertNull(r[0].dateOfBirth)
        assertNull(r[0].nationality)
        assertNull(r[0].docNumber)
        assertEquals(false, r[0].isCrew)
    }

    @Test
    fun `throws on empty data`() {
        assertThrows(CsvImportException::class.java) { PeopleCsv.parse("") }
    }

    @Test
    fun `throws on missing required columns`() {
        val e = assertThrows(CsvImportException::class.java) { PeopleCsv.parse("Nickname,Age\nx,1") }
        assertTrue(e.message!!.contains("first name"))
        assertTrue(e.message!!.contains("last name"))
    }

    @Test
    fun `throws if only first name is present`() {
        val e = assertThrows(CsvImportException::class.java) { PeopleCsv.parse("First Name\nAnna") }
        assertTrue(e.message!!.contains("last name"))
    }

    @Test
    fun `skips rows with empty first and last name`() {
        val r = PeopleCsv.parse("First Name,Last Name\nAnna,Eriksson\n,\nBo,Lindqvist")
        assertEquals(listOf("Anna", "Bo"), r.map { it.firstName })
    }

    @Test
    fun `handles quoted fields with commas`() {
        val r = PeopleCsv.parse("First Name,Last Name\n\"Anna, Marie\",Eriksson")
        assertEquals("Anna, Marie", r[0].firstName)
    }

    @Test
    fun `handles doubled quotes inside a quoted field`() {
        val r = PeopleCsv.parse("First Name,Last Name\n\"An\"\"na\",Eriksson")
        assertEquals("An\"na", r[0].firstName)
    }

    @Test
    fun `header is case-insensitive`() {
        val r = PeopleCsv.parse("FIRST NAME,last name,GeNdEr\nAnna,Eriksson,F")
        assertEquals("Anna", r[0].firstName)
        assertEquals("F", r[0].sex)
    }

    @Test
    fun `empty optional fields become null`() {
        val r = PeopleCsv.parse("$fullHeader\nAnna,Eriksson,,,,,,,,")
        assertNull(r[0].sex)
        assertNull(r[0].dateOfBirth)
        assertNull(r[0].docNumber)
    }

    @Test
    fun `crew type detection is case-insensitive`() {
        val r = PeopleCsv.parse("First Name,Last Name,Type\nA,B,CREW\nC,D,crew\nE,F,Passenger")
        assertEquals(listOf(true, true, false), r.map { it.isCrew })
    }

    @Test
    fun `invalid date returns null rather than throwing`() {
        val r = PeopleCsv.parse("First Name,Last Name,DoB\nAnna,Eriksson,not-a-date")
        assertNull(r[0].dateOfBirth)
    }

    @Test
    fun `multiple rows parsed correctly`() {
        val r = PeopleCsv.parse("First Name,Last Name\nA,One\nB,Two\nC,Three")
        assertEquals(3, r.size)
        assertEquals(listOf("One", "Two", "Three"), r.map { it.lastName })
    }

    // --- Beyond the Swift suite ---

    @Test
    fun `CRLF line endings are handled`() {
        val r = PeopleCsv.parse("First Name,Last Name\r\nAnna,Eriksson\r\nBo,Lindqvist\r\n")
        assertEquals(2, r.size)
    }

    @Test
    fun `a UTF-8 BOM does not hide the first column`() {
        // Swift strips the BOM when decoding; Kotlin does not, so the parser must.
        val r = PeopleCsv.parse("﻿First Name,Last Name\nAnna,Eriksson")
        assertEquals("Anna", r[0].firstName)
    }

    private fun known(first: String, last: String, dob: LocalDate?, vararg docs: String) =
        PeopleCsv.KnownPerson("id-$last", first, last, dob, docs.toSet())

    @Test
    fun `plan skips people already held without a new document`() {
        val parsed = PeopleCsv.parse(
            "First Name,Last Name,DoB\nAnna,Eriksson,1974-08-12\nBo,Lindqvist,1980-01-01",
        )
        val plan = PeopleCsv.plan(parsed, listOf(known("anna", "ERIKSSON", LocalDate.of(1974, 8, 12))))
        assertEquals(1, plan.skipped)
        assertEquals(listOf("Lindqvist"), plan.newPeople.map { it.person.lastName })
    }

    @Test
    fun `plan also dedupes within the file itself`() {
        val parsed = PeopleCsv.parse("First Name,Last Name\nAnna,Eriksson\nAnna,Eriksson")
        val plan = PeopleCsv.plan(parsed, emptyList())
        assertEquals(1, plan.newPeople.size)
        assertEquals(1, plan.skipped)
    }

    @Test
    fun `same name different birthday is not a duplicate`() {
        val parsed = PeopleCsv.parse(
            "First Name,Last Name,DoB\nAnna,Eriksson,1974-08-12\nAnna,Eriksson,1990-02-02",
        )
        assertEquals(2, PeopleCsv.plan(parsed, emptyList()).newPeople.size)
    }

    // Ported from iOS `CSVImportTests` (1173620).
    private val importHeader = "First Name,Last Name,DoB,Doc Type,Doc Number,Doc Expiry,Doc Issuing State"

    @Test
    fun `same person on several rows becomes one person with several documents`() {
        val plan = PeopleCsv.plan(
            PeopleCsv.parse(
                "$importHeader\n" +
                    "Zara,Kowalski,1985-03-22,Passport,PP-1,2030-06-15,XYZ\n" +
                    "Zara,Kowalski,1985-03-22,Identity card,ID-2,2031-01-01,ABC",
            ),
            emptyList(),
        )
        assertEquals(1, plan.imported)
        assertEquals(1, plan.documentsAdded)
        assertEquals(0, plan.skipped)
        assertEquals(1, plan.newPeople.size)
        assertEquals(setOf("PP-1", "ID-2"), plan.newPeople[0].documents.map { it.docNumber }.toSet())
    }

    @Test
    fun `re-import adds new documents to an existing person and skips known ones`() {
        val plan = PeopleCsv.plan(
            PeopleCsv.parse(
                "$importHeader\n" +
                    "Zara,Kowalski,1985-03-22,Passport,PP-1,,\n" +
                    "Zara,Kowalski,1985-03-22,Passport,PP-3,,",
            ),
            listOf(known("Zara", "Kowalski", LocalDate.of(1985, 3, 22), "PP-1")),
        )
        assertEquals(0, plan.imported)
        assertEquals(1, plan.documentsAdded)
        assertEquals(1, plan.skipped)
        assertEquals(listOf("PP-3"), plan.documentsForExisting.map { it.row.docNumber })
        assertEquals("id-Kowalski", plan.documentsForExisting[0].personId)
    }

    @Test
    fun `a document repeated in the file is added once`() {
        val plan = PeopleCsv.plan(
            PeopleCsv.parse(
                "$importHeader\n" +
                    "Zara,Kowalski,1985-03-22,Passport,PP-1,,\n" +
                    "Zara,Kowalski,1985-03-22,Passport,PP-1,,",
            ),
            emptyList(),
        )
        assertEquals(1, plan.imported)
        assertEquals(0, plan.documentsAdded)
        assertEquals(1, plan.skipped)
        assertEquals(1, plan.newPeople[0].documents.size)
    }

    @Test
    fun `summary reads like iOS`() {
        val plan = PeopleCsv.ImportPlan(emptyList(), emptyList(), imported = 2, documentsAdded = 1, skipped = 3)
        assertEquals("2 imported, 1 document added, 3 already existed.", plan.summary)
    }

    @Test
    fun `export round-trips through parse, one row per document`() {
        val csv = PeopleCsv.export(
            listOf(
                PeopleCsv.ExportPerson(
                    "Anna", "Eriksson, Jr", "Female", LocalDate.of(1974, 8, 12), isCrew = true,
                    documents = listOf(
                        PeopleCsv.ExportDocument("Passport", "P1", LocalDate.of(2031, 6, 30), "FRA"),
                        PeopleCsv.ExportDocument("Identity card", "I2", null, "DEU"),
                    ),
                ),
                PeopleCsv.ExportPerson("Bo", "Lind\"qvist", null, null, isCrew = false, documents = emptyList()),
            ),
        )
        val rows = PeopleCsv.parse(csv)
        assertEquals(3, rows.size)
        assertEquals("Eriksson, Jr", rows[0].lastName)
        assertEquals(listOf("P1", "I2"), rows.take(2).map { it.docNumber })
        assertEquals("DEU", rows[1].nationality)
        assertTrue(rows[0].isCrew)
        assertEquals("Lind\"qvist", rows[2].lastName)
        assertNull(rows[2].docNumber)

        val plan = PeopleCsv.plan(rows, emptyList())
        assertEquals(2, plan.imported)
        assertEquals(1, plan.documentsAdded)
    }

    @Test
    fun `sex from the template's letters becomes the editor's words`() {
        assertEquals("Male", PeopleCsv.normaliseSex("M"))
        assertEquals("Female", PeopleCsv.normaliseSex(" female "))
        assertNull(PeopleCsv.normaliseSex(""))
        assertEquals("X", PeopleCsv.normaliseSex("X"))
    }
}
