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

    @Test
    fun `plan skips people already held`() {
        val parsed = PeopleCsv.parse(
            "First Name,Last Name,DoB\nAnna,Eriksson,1974-08-12\nBo,Lindqvist,1980-01-01",
        )
        val existing = setOf(PeopleCsv.dedupKey("anna", "ERIKSSON", LocalDate.of(1974, 8, 12)))
        val plan = PeopleCsv.plan(parsed, existing)
        assertEquals(1, plan.skipped)
        assertEquals(listOf("Lindqvist"), plan.toImport.map { it.lastName })
    }

    @Test
    fun `plan also dedupes within the file itself`() {
        val parsed = PeopleCsv.parse("First Name,Last Name\nAnna,Eriksson\nAnna,Eriksson")
        val plan = PeopleCsv.plan(parsed, emptySet())
        assertEquals(1, plan.toImport.size)
        assertEquals(1, plan.skipped)
    }

    @Test
    fun `same name different birthday is not a duplicate`() {
        val parsed = PeopleCsv.parse(
            "First Name,Last Name,DoB\nAnna,Eriksson,1974-08-12\nAnna,Eriksson,1990-02-02",
        )
        assertEquals(2, PeopleCsv.plan(parsed, emptySet()).toImport.size)
    }
}
