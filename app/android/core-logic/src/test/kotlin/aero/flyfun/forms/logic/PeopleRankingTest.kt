package aero.flyfun.forms.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class PeopleRankingTest {

    private fun day(n: Long) = Instant.parse("2026-01-01T00:00:00Z").plusSeconds(n * 86_400)

    @Test
    fun `search matches first, last or full name, ignoring case`() {
        assertTrue(PeopleRanking.matches("ann", "Anna", "Eriksson"))
        assertTrue(PeopleRanking.matches("ERIK", "Anna", "Eriksson"))
        assertTrue(PeopleRanking.matches("anna eri", "Anna", "Eriksson"))
        assertTrue(PeopleRanking.matches("  ", "Anna", "Eriksson"))
        assertFalse(PeopleRanking.matches("bo", "Anna", "Eriksson"))
    }

    @Test
    fun `recent order puts the last flown first and the never flown last`() {
        val people = listOf(
            RankedPerson("a", "A", "Never"),
            RankedPerson("b", "B", "Old", lastFlight = day(1)),
            RankedPerson("c", "C", "New", lastFlight = day(9)),
        )
        assertEquals(listOf("c", "b", "a"), PeopleRanking.byRecent(people).map { it.id })
    }

    @Test
    fun `picker puts usual crew first, then recent, then by name`() {
        val people = listOf(
            RankedPerson("pax-old", "P", "Old", lastFlight = day(1)),
            RankedPerson("crew-b", "C", "Bravo", isUsualCrew = true),
            RankedPerson("pax-new", "P", "New", lastFlight = day(5)),
            RankedPerson("crew-a", "C", "Alpha", isUsualCrew = true),
            RankedPerson("pax-z", "P", "Zulu"),
            RankedPerson("pax-a", "P", "alpha"),
        )
        assertEquals(
            listOf("crew-a", "crew-b", "pax-new", "pax-old", "pax-a", "pax-z"),
            PeopleRanking.forPicker(people).map { it.id },
        )
    }

    @Test
    fun `co-travelers need two flights together and come most frequent first`() {
        val flights = listOf(
            FlightPeople("1", day(1), crew = listOf("me"), passengers = listOf("often", "once")),
            FlightPeople("2", day(2), crew = listOf("me", "often"), passengers = listOf("twice")),
            FlightPeople("3", day(3), crew = listOf("often"), passengers = listOf("me", "twice")),
            FlightPeople("4", day(4), crew = listOf("stranger"), passengers = listOf("often")),
        )
        assertEquals(listOf("often", "twice"), PeopleRanking.coTravelers("me", flights))
        assertEquals(listOf("often", "twice", "once"), PeopleRanking.coTravelers("me", flights, minimumFlights = 1))
    }

    @Test
    fun `split name as the picker does`() {
        assertEquals("" to "Smith", PeopleRanking.splitName("Smith"))
        assertEquals("Jane" to "van Dijk", PeopleRanking.splitName(" Jane  van Dijk "))
    }

    @Test
    fun `a person in both roles stays crew`() {
        val (crew, pax) = PeopleRanking.withoutDuplicates(listOf("a", "b", "a"), listOf("b", "c", "c"))
        assertEquals(listOf("a", "b"), crew)
        assertEquals(listOf("c"), pax)
    }
}
