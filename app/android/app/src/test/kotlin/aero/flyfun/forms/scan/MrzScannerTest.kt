package aero.flyfun.forms.scan

import aero.flyfun.forms.logic.MRZParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Line extraction is the part of scanning that can be tested without a camera,
 * so it is. Parsing itself is covered by MRZParserTest in :core-logic.
 */
class MrzScannerTest {

    private val line1 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
    private val line2 = "L898902C36UTO7408122F1204159ZE184226B<<<<<10"

    @Test
    fun `picks the two MRZ lines out of a page of other text`() {
        val ocr = """
            PASSPORT
            Type P  Code UTO  Passport No L898902C3
            Surname ERIKSSON
            $line1
            $line2
        """.trimIndent()
        val lines = MrzScanner.candidateLines(ocr)
        assertNotNull(lines)
        assertEquals(2, lines!!.size)
        assertNotNull("the extracted lines must actually parse", MRZParser.parse(lines))
    }

    @Test
    fun `tolerates the spaces OCR inserts`() {
        val ocr = "$line1\n${line2.chunked(11).joinToString(" ")}"
        assertNotNull(MRZParser.parse(MrzScanner.candidateLines(ocr)!!))
    }

    @Test
    fun `normalises the guillemet OCR sometimes returns for a filler`() {
        val ocr = line1.replace("<", "«") + "\n" + line2
        assertNotNull(MRZParser.parse(MrzScanner.candidateLines(ocr)!!))
    }

    @Test
    fun `pads a line the OCR cut short`() {
        val ocr = "${line1.dropLast(1)}\n$line2"
        val lines = MrzScanner.candidateLines(ocr)!!
        assertEquals(44, lines[0].length)
        assertNotNull(MRZParser.parse(lines))
    }

    @Test
    fun `picks TD1 when three short lines are present`() {
        val ocr = """
            IDENTITY CARD
            I<UTOD231458907<<<<<<<<<<<<<<<
            7408122F1204159UTO<<<<<<<<<<<6
            ERIKSSON<<ANNA<MARIA<<<<<<<<<<
        """.trimIndent()
        val lines = MrzScanner.candidateLines(ocr)!!
        assertEquals(3, lines.size)
        assertNotNull(MRZParser.parse(lines))
    }

    @Test
    fun `returns null when there is no MRZ in view`() {
        assertNull(MrzScanner.candidateLines("BOARDING PASS\nGate 42\nSeat 12A"))
    }

    @Test
    fun `ignores prose of about the right length`() {
        // Punctuation disqualifies a line, so a sentence cannot masquerade as MRZ.
        assertNull(
            MrzScanner.candidateLines(
                "This line is about forty-four characters!!\nAnd so is this one, more or less, yes.",
            ),
        )
    }
}
