package aero.flyfun.forms.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class ContactImportTest {

    private val people = listOf(
        ContactImport.Candidate("zara", "Zara", "Kowalski"),
        ContactImport.Candidate("zarah", "Zarah", "Kowalsky"),
        ContactImport.Candidate("ola", "Ola", "Nowak"),
        ContactImport.Candidate("alex", "Alexandra", "Kowalski"),
    )

    @Test
    fun `exact first, then same surname by prefix, then within two edits`() {
        val found = ContactImport.matches(ImportedContact("Zara", "Kowalski"), people)
        assertEquals("zara", found.first())
        assertTrue("zarah" in found)
        assertTrue("ola" !in found)
    }

    @Test
    fun `a shortened first name matches on its first three letters`() {
        assertEquals(listOf("alex"), ContactImport.matches(ImportedContact("Alex", "Kowalski"), people).filter { it == "alex" })
    }

    @Test
    fun `a contact with no name matches nobody`() {
        assertTrue(ContactImport.matches(ImportedContact("", ""), people).isEmpty())
    }

    @Test
    fun `levenshtein counts edits`() {
        assertEquals(0, ContactImport.levenshtein("abc", "abc"))
        assertEquals(1, ContactImport.levenshtein("kowalski", "kowalsky"))
        assertEquals(3, ContactImport.levenshtein("", "abc"))
        assertEquals(2, ContactImport.levenshtein("zara", "sarah"))
    }

    private val person = ContactFields("Zara", "Kowalski", phone = "+44 1", email = null, address = "", dateOfBirth = null)
    private val contact = ImportedContact("Zarah", "Kowalsky", dateOfBirth = LocalDate.of(1985, 3, 22))

    @Test
    fun `fill missing only keeps what the person has`() {
        val merged = ContactImport.merge(person, contact, phone = "+44 2", email = "z@x", address = "1 Road", override = false)
        assertEquals("Zara", merged.firstName)
        assertEquals("+44 1", merged.phone)
        assertEquals("z@x", merged.email)
        assertEquals("1 Road", merged.address)
        assertEquals(LocalDate.of(1985, 3, 22), merged.dateOfBirth)
    }

    @Test
    fun `override all takes the contact's name and values, keeping what it lacks`() {
        val merged = ContactImport.merge(person, contact, phone = "+44 2", email = null, address = null, override = true)
        assertEquals("Zarah", merged.firstName)
        assertEquals("Kowalsky", merged.lastName)
        assertEquals("+44 2", merged.phone)
        assertNull(merged.email)
        assertEquals("", merged.address)
    }

    @Test
    fun `address and birthday come out of Android's shapes`() {
        assertEquals("1 Road, Leeds, LS1, UK", ContactImport.addressLine("1 Road", "Leeds", " LS1 ", "UK"))
        assertNull(ContactImport.addressLine(null, "", " ", null))
        assertEquals(LocalDate.of(1985, 3, 22), ContactImport.parseBirthday("1985-03-22"))
        assertNull(ContactImport.parseBirthday("--03-22"))
        assertNull(ContactImport.parseBirthday("garbage"))
    }
}
