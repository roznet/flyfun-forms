package aero.flyfun.forms.logic

import org.junit.Assert.assertEquals
import org.junit.Test

class EmailTextTest {

    @Test
    fun `spoken languages round trip in the iOS storage format`() {
        assertEquals("de,fr", SpokenLanguages.serialize(setOf("fr", "de")))
        assertEquals(setOf("fr", "de"), SpokenLanguages.parse(" fr, de ,"))
        assertEquals(emptySet<String>(), SpokenLanguages.parse(null))
    }

    @Test
    fun `the body is local when the pilot speaks the airport's language`() {
        val message = EmailText.choose("fr", setOf("fr"), "LFOH", "ppf le havre octeville", "Hello", "Bonjour")
        assertEquals(EmailText.Message("ppf le havre octeville", "Bonjour"), message)
    }

    @Test
    fun `otherwise the body is English and the subject still local`() {
        assertEquals(
            EmailText.Message("LFOH 2026-10-01", "Hello"),
            EmailText.choose("fr", setOf("de"), "en", "LFOH 2026-10-01", "Hello", "Bonjour"),
        )
        assertEquals("Hello", EmailText.choose(null, setOf("fr"), "s", "s", "Hello", "Bonjour").body)
    }

    @Test
    fun `an empty local subject falls back to the English one`() {
        assertEquals("Customs - LFOH", EmailText.choose(null, emptySet(), "Customs - LFOH", "", "b", "").subject)
    }

    @Test
    fun `the fallback reads like the iOS one`() {
        val message = EmailText.fallback("Préavis Douane", "EGTF", "LFOH", "2026-10-01", "ZZ-TEST")
        assertEquals("Préavis Douane - LFOH - 2026-10-01 - ZZ-TEST", message.subject)
        assertEquals(
            "Please find attached the Préavis Douane for flight EGTF → LFOH on 2026-10-01, aircraft ZZ-TEST.",
            message.body,
        )
    }
}
