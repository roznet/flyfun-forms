package aero.flyfun.forms.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Duration
import java.time.Instant

/** Ported from iOS `FlightImportTests.swift` (NextOccurrenceTests, PeopleSuggestionTests). */
class NewFlightTest {

    private fun utc(y: Int, m: Int, d: Int, h: Int, min: Int) =
        Instant.parse("%04d-%02d-%02dT%02d:%02d:00Z".format(y, m, d, h, min))

    // --- Next occurrence

    @Test
    fun `keeps the time of day and lands today when it is still ahead`() {
        val (dep, _) = NextOccurrence.of(utc(2026, 3, 1, 14, 30), utc(2026, 3, 1, 16, 0), utc(2026, 9, 16, 9, 0))
        assertEquals(utc(2026, 9, 16, 14, 30), dep)
    }

    @Test
    fun `rolls to tomorrow once the time of day has passed`() {
        val (dep, _) = NextOccurrence.of(utc(2026, 3, 1, 8, 0), utc(2026, 3, 1, 9, 30), utc(2026, 9, 16, 9, 0))
        assertEquals(utc(2026, 9, 17, 8, 0), dep)
    }

    @Test
    fun `carries the leg's duration rather than realigning onto the day`() {
        val (dep, arr) = NextOccurrence.of(utc(2026, 3, 1, 22, 0), utc(2026, 3, 2, 1, 30), utc(2026, 9, 16, 9, 0))
        assertEquals(utc(2026, 9, 16, 22, 0), dep)
        assertEquals(utc(2026, 9, 17, 1, 30), arr)
        assertEquals(Duration.ofMinutes(210), Duration.between(dep, arr))
    }

    @Test
    fun `reads the time of day in the origin's zone, not UTC`() {
        // 09:00 in Zurich in June (UTC+2) repeats as 09:00 local, 07:00Z, in September.
        val (dep, _) = NextOccurrence.of(
            utc(2026, 6, 1, 7, 0), utc(2026, 6, 1, 8, 30), utc(2026, 9, 16, 4, 0), zone = "Europe/Zurich",
        )
        assertEquals(utc(2026, 9, 16, 7, 0), dep)
    }

    @Test
    fun `keeps the local time across a DST change`() {
        // 09:00 in Zurich in summer (07:00Z) repeated in winter is 08:00Z.
        val (dep, _) = NextOccurrence.of(
            utc(2026, 6, 1, 7, 0), utc(2026, 6, 1, 8, 0), utc(2026, 12, 1, 4, 0), zone = "Europe/Zurich",
        )
        assertEquals(utc(2026, 12, 1, 8, 0), dep)
    }

    @Test
    fun `a flight with no arrival time does not produce one before departure`() {
        val (dep, arr) = NextOccurrence.of(utc(2026, 3, 1, 14, 0), utc(2026, 3, 1, 0, 0), utc(2026, 9, 16, 9, 0))
        assertEquals(dep, arr)
    }

    // --- People suggestion

    private fun flight(id: String, day: Int, aircraft: String?, crew: List<String>, pax: List<String> = emptyList()) =
        FlightPeople(id, utc(2026, 1, day, 10, 0), aircraft, crew, pax)

    @Test
    fun `prefers the most recent flight in the same aircraft`() {
        val older = flight("older", 1, "piper", listOf("ola"))
        val newer = flight("newer", 20, "cessna", listOf("zara"))
        assertEquals(listOf("ola"), PeopleSuggestion.suggest(listOf(newer, older), "piper", emptyList())?.crew)
    }

    @Test
    fun `falls back to the most recent flight when the aircraft is unknown`() {
        val s = PeopleSuggestion.suggest(listOf(flight("f", 1, null, listOf("zara"))), null, emptyList())
        assertEquals("f", s?.fromFlightId)
        assertEquals(1, s?.crew?.size)
    }

    @Test
    fun `falls back to usual crew when no flight has people`() {
        val s = PeopleSuggestion.suggest(listOf(flight("empty", 1, null, emptyList())), null, listOf("zara"))
        assertEquals(listOf("zara"), s?.crew)
        assertNull(s?.fromFlightId)
    }

    @Test
    fun `suggests nothing at all on a first run`() = assertNull(PeopleSuggestion.suggest(emptyList(), null, emptyList()))

    @Test
    fun `the crew sources skip empty flights, newest first`() {
        val sources = PeopleSuggestion.crewSources(
            listOf(flight("older", 1, null, listOf("ola")), flight("newer", 2, null, listOf("zara")), flight("empty", 3, null, emptyList())),
        )
        assertEquals(listOf("newer", "older"), sources.map { it.flightId })
    }

    @Test
    fun `the same people on two trips are offered once`() {
        val sources = PeopleSuggestion.crewSources(
            listOf(flight("first", 1, null, listOf("zara")), flight("second", 8, null, listOf("zara"))),
        )
        assertEquals(listOf("second"), sources.map { it.flightId })
    }

    @Test
    fun `summary names two and counts the rest`() {
        assertEquals("", PeopleSuggestion.summary(emptyList()))
        assertEquals("Anne, Bob", PeopleSuggestion.summary(listOf("Anne", "Bob")))
        assertEquals("Anne, Bob and 2 more", PeopleSuggestion.summary(listOf("Anne", "Bob", "Cy", "Di")))
    }
}
