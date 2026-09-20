package aero.flyfun.forms.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate

/**
 * Ported from `flyfun-formsTests/DocumentResolverTests.swift`.
 * The Swift tests are the specification; keep them in step.
 */
class DocumentResolverTest {

    private var seq = 0

    private fun doc(
        number: String,
        country: String?,
        expiry: LocalDate?,
        type: String = "Passport",
        isActive: Boolean = true,
    ) = ResolvableDocument(
        id = "doc-${seq++}",
        docType = type,
        docNumber = number,
        issuingCountry = country,
        expiryDate = expiry,
        isActive = isActive,
    )

    private fun date(y: Int, m: Int, d: Int) = LocalDate.of(y, m, d)

    @Test
    fun `no documents returns null`() {
        assertNull(DocumentResolver.resolve(emptyList(), "LSGS"))
    }

    @Test
    fun `single document is always returned`() {
        val docs = listOf(doc("PP-100001", "XYZ", date(2030, 6, 15)))
        assertEquals("PP-100001", DocumentResolver.resolve(docs, "LSGS")?.docNumber)
    }

    @Test
    fun `schengen airport prefers schengen-issued document`() {
        val docs = listOf(
            doc("PP-GBR-001", "GBR", date(2031, 1, 1)),
            doc("ID-FRA-001", "FRA", date(2029, 6, 1), type = "Identity card"),
        )
        // LSGS is LS prefix -> Schengen -> should pick the FRA document
        assertEquals("ID-FRA-001", DocumentResolver.resolve(docs, "LSGS")?.docNumber)
    }

    @Test
    fun `uk airport prefers GBR-issued document`() {
        val docs = listOf(
            doc("ID-FRA-001", "FRA", date(2029, 6, 1), type = "Identity card"),
            doc("PP-GBR-001", "GBR", date(2031, 1, 1)),
        )
        assertEquals("PP-GBR-001", DocumentResolver.resolve(docs, "EGKA")?.docNumber)
    }

    @Test
    fun `french airport LF is schengen - picks FRA over GBR`() {
        val docs = listOf(
            doc("PP-GBR-001", "GBR", date(2031, 1, 1)),
            doc("PP-FRA-001", "FRA", date(2029, 1, 1)),
        )
        assertEquals("PP-FRA-001", DocumentResolver.resolve(docs, "LFAC")?.docNumber)
    }

    @Test
    fun `no region match falls back to latest expiry`() {
        val docs = listOf(
            doc("PP-EARLY", "XYZ", date(2028, 1, 1)),
            doc("PP-LATE", "ABC", date(2032, 12, 31)),
        )
        // ZZZZ is an unknown prefix -> OTHER -> no region match -> latest expiry
        assertEquals("PP-LATE", DocumentResolver.resolve(docs, "ZZZZ")?.docNumber)
    }

    @Test
    fun `region match tiebreak by latest expiry`() {
        val docs = listOf(
            doc("ID-DEU-001", "DEU", date(2028, 1, 1), type = "Identity card"),
            doc("PP-FRA-001", "FRA", date(2032, 6, 1)),
            doc("PP-GBR-001", "GBR", date(2033, 1, 1)),
        )
        // LSGS is Schengen -> DEU and FRA match -> FRA has the later expiry.
        // The GBR document has the latest expiry overall and must NOT win.
        assertEquals("PP-FRA-001", DocumentResolver.resolve(docs, "LSGS")?.docNumber)
    }

    @Test
    fun `uk airport with no GBR document falls back to latest expiry`() {
        val docs = listOf(
            doc("PP-FRA-001", "FRA", date(2028, 1, 1)),
            doc("PP-USA-001", "USA", date(2032, 6, 1)),
        )
        assertEquals("PP-USA-001", DocumentResolver.resolve(docs, "EGLL")?.docNumber)
    }

    @Test
    fun `null expiry dates are sorted last`() {
        val docs = listOf(
            doc("PP-NIL", "XYZ", null),
            doc("PP-DATED", "ABC", date(2027, 1, 1)),
        )
        assertEquals("PP-DATED", DocumentResolver.resolve(docs, "ZZZZ")?.docNumber)
    }

    @Test
    fun `multiple schengen prefixes recognized`() {
        val docs = listOf(
            doc("PP-GBR-001", "GBR", date(2031, 1, 1)),
            doc("PP-ITA-001", "ITA", date(2029, 1, 1)),
        )
        for (airport in listOf("EDDF", "EBBR", "LIRF")) {
            assertEquals(
                "Expected ITA doc for Schengen airport $airport",
                "PP-ITA-001",
                DocumentResolver.resolve(docs, airport)?.docNumber,
            )
        }
    }

    // --- Beyond the Swift suite: behaviour the Swift code has but never asserted ---

    @Test
    fun `inactive documents are ignored`() {
        val docs = listOf(
            doc("PP-INACTIVE", "FRA", date(2033, 1, 1), isActive = false),
            doc("PP-ACTIVE", "FRA", date(2029, 1, 1)),
        )
        assertEquals("PP-ACTIVE", DocumentResolver.resolve(docs, "LFAC")?.docNumber)
    }

    @Test
    fun `all documents inactive returns null`() {
        val docs = listOf(doc("PP-1", "FRA", date(2033, 1, 1), isActive = false))
        assertNull(DocumentResolver.resolve(docs, "LFAC"))
    }

    @Test
    fun `override wins over region match`() {
        val gbr = doc("PP-GBR-001", "GBR", date(2031, 1, 1))
        val fra = doc("PP-FRA-001", "FRA", date(2029, 1, 1))
        // LFAC is Schengen so FRA would normally win; the override must beat it.
        assertEquals(
            "PP-GBR-001",
            DocumentResolver.resolve(listOf(gbr, fra), "LFAC", overrideDocumentId = gbr.id)?.docNumber,
        )
    }

    @Test
    fun `stale override id is ignored`() {
        val docs = listOf(
            doc("PP-GBR-001", "GBR", date(2031, 1, 1)),
            doc("PP-FRA-001", "FRA", date(2029, 1, 1)),
        )
        assertEquals(
            "PP-FRA-001",
            DocumentResolver.resolve(docs, "LFAC", overrideDocumentId = "no-such-doc")?.docNumber,
        )
    }
}
