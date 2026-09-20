package aero.flyfun.forms.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate

/**
 * Ported from `flyfun-formsTests/MRZParserTests.swift`.
 *
 * The Swift suite reads the century rule against the real clock; here a fixed
 * [today] is passed so the expectations cannot rot as years pass.
 */
class MRZParserTest {

    private val today = LocalDate.of(2026, 9, 19)

    // --- Check digit ---

    @Test
    fun `ICAO check digit for known passport number`() {
        // L898902C3 -> 6 (ICAO specimen)
        assertEquals(6, MRZParser.checkDigit("L898902C3"))
    }

    @Test
    fun `check digit for all-filler string is zero`() {
        assertEquals(0, MRZParser.checkDigit("<<<"))
    }

    @Test
    fun `check digit for digits only`() {
        // 7*7 + 4*3 + 0*1 + 8*7 + 1*3 + 2*1 = 122 -> 2
        assertEquals(2, MRZParser.checkDigit("740812"))
    }

    // --- Sanitization ---

    @Test
    fun `sanitize common OCR misreads`() {
        assertEquals("0185", MRZParser.sanitizeDigits("O1B5"))
        assertEquals("5106", MRZParser.sanitizeDigits("SIQG"))
        assertEquals("123", MRZParser.sanitizeDigits("123"))
    }

    // --- Dates ---

    @Test
    fun `birth date with year greater than current maps to 1900s`() {
        assertEquals(LocalDate.of(1974, 8, 12), MRZParser.parseMRZDate("740812", true, today))
    }

    @Test
    fun `birth date with year at or below current maps to 2000s`() {
        assertEquals(LocalDate.of(2005, 3, 15), MRZParser.parseMRZDate("050315", true, today))
    }

    @Test
    fun `expiry date is always 2000s`() {
        assertEquals(LocalDate.of(2012, 4, 15), MRZParser.parseMRZDate("120415", false, today))
    }

    @Test
    fun `invalid date returns null`() {
        assertNull(MRZParser.parseMRZDate("001301", true, today)) // month 13
        assertNull(MRZParser.parseMRZDate("AB0101", true, today)) // non-digit
        assertNull(MRZParser.parseMRZDate("12", true, today))     // too short
    }

    // --- TD3 (passport) ---

    private val specimenLine1 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
    private val specimenLine2 = "L898902C36UTO7408122F1204159ZE184226B<<<<<10"

    @Test
    fun `ICAO specimen passport parses correctly`() {
        val r = MRZParser.parse(listOf(specimenLine1, specimenLine2), today)
        assertNotNull(r)
        requireNotNull(r)
        assertEquals("Eriksson", r.surname)
        assertEquals("Anna Maria", r.givenNames)
        assertEquals("L898902C3", r.passportNumber)
        assertEquals("UTO", r.nationality)
        assertEquals("UTO", r.issuingCountry)
        assertEquals("F", r.gender)
        assertEquals(MRZFormat.TD3, r.format)
        assertEquals(LocalDate.of(1974, 8, 12), r.dateOfBirth)
        assertEquals(LocalDate.of(2012, 4, 15), r.expiryDate)
    }

    @Test
    fun `TD3 with bad check digit returns null`() {
        // Last digit 0 -> 9 breaks the composite check
        val bad = "L898902C36UTO7408122F1204159ZE184226B<<<<<19"
        assertNull(MRZParser.parse(listOf(specimenLine1, bad), today))
    }

    @Test
    fun `TD3 male gender`() {
        val line2 = "L898902C36UTO7408122M1204159ZE184226B<<<<<10"
        assertEquals("M", MRZParser.parse(listOf(specimenLine1, line2), today)?.gender)
    }

    @Test
    fun `TD3 unspecified gender`() {
        val line2 = "L898902C36UTO7408122<1204159ZE184226B<<<<<10"
        assertEquals("X", MRZParser.parse(listOf(specimenLine1, line2), today)?.gender)
    }

    // --- TD1 (ID card) ---

    @Test
    fun `TD1 ID card parses correctly`() {
        val line1 = "I<UTOD231458907<<<<<<<<<<<<<<<"
        val line2 = "7408122F1204159UTO<<<<<<<<<<<6"
        val line3 = "ERIKSSON<<ANNA<MARIA<<<<<<<<<<"
        val r = MRZParser.parse(listOf(line1, line2, line3), today)
        assertNotNull(r)
        requireNotNull(r)
        assertEquals("Eriksson", r.surname)
        assertEquals("Anna Maria", r.givenNames)
        assertEquals("D23145890", r.passportNumber)
        assertEquals("UTO", r.nationality)
        assertEquals("UTO", r.issuingCountry)
        assertEquals("F", r.gender)
        assertEquals(MRZFormat.TD1, r.format)
    }

    // --- Malformed input ---

    @Test
    fun `wrong number of lines returns null`() {
        assertNull(MRZParser.parse(listOf("ONELINE"), today))
        assertNull(MRZParser.parse(emptyList(), today))
    }

    @Test
    fun `wrong line length returns null`() {
        assertNull(MRZParser.parse(listOf("SHORT", "ALSO_SHORT"), today))
    }

    @Test
    fun `names with single component`() {
        val line1 = "P<UTOMADONNA<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"
        val r = MRZParser.parse(listOf(line1, specimenLine2), today)
        assertEquals("Madonna", r?.surname)
        assertEquals("", r?.givenNames)
    }

    // --- Beyond the Swift suite ---

    @Test
    fun `correctField recovers a single OCR substitution`() {
        // D23145890 has check digit 7. The MRZ font makes D and 0 easy to confuse,
        // so a scan may deliver 023145890 - which fails its own checksum.
        assertEquals(7, MRZParser.checkDigit("D23145890"))
        assertEquals("D23145890", MRZParser.correctField("023145890", 7))
    }

    @Test
    fun `correctField gives up when no substitution satisfies the checksum`() {
        assertNull(MRZParser.correctField("ZZZZZZZZZ", 7))
    }

    @Test
    fun `century boundary respects the supplied today`() {
        // With today in 2026, yy=27 is last century; in 2028 it would be this one.
        assertEquals(LocalDate.of(1927, 1, 1), MRZParser.parseMRZDate("270101", true, today))
        assertEquals(
            LocalDate.of(2027, 1, 1),
            MRZParser.parseMRZDate("270101", true, LocalDate.of(2028, 1, 1)),
        )
    }

    @Test
    fun `impossible calendar date is rejected`() {
        // 31 February. Swift's lenient Calendar rolls this into March; we reject it.
        assertNull(MRZParser.parseMRZDate("740231", true, today))
    }
}
