package aero.flyfun.forms.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class AirportsTest {

    private val airports = listOf(
        AirportSummary("EGLL", "London Heathrow Airport", "London", "GB", "large_airport", "LHR"),
        AirportSummary("EGKB", "London Biggin Hill Airport", "London", "GB", "medium_airport", "BQH"),
        AirportSummary("EGLC", "London City Airport", "London", "GB", "medium_airport", "LCY"),
        AirportSummary("LFAC", "Calais-Dunkerque Airport", "Calais", "FR", "small_airport"),
        AirportSummary("LFPB", "Paris-Le Bourget Airport", "Paris", "FR", "large_airport", "LBG"),
    )

    @Test
    fun `exact code first, then code prefix, then bigger airports`() {
        assertEquals("EGLL", AirportSearch.rank("egll", airports).first().icao)
        assertEquals(listOf("EGLL", "EGLC"), AirportSearch.rank("EGL", airports).map { it.icao })
        assertEquals("EGLC", AirportSearch.rank("LCY", airports).first().icao)
    }

    @Test
    fun `names match at a word start and anywhere`() {
        assertEquals(listOf("EGLL", "EGKB", "EGLC"), AirportSearch.rank("london", airports).map { it.icao })
        assertEquals(listOf("LFPB"), AirportSearch.rank("bourget", airports).map { it.icao })
        assertEquals(listOf("LFAC"), AirportSearch.rank("dunk", airports).map { it.icao })
        assertTrue(AirportSearch.rank("  ", airports).isEmpty())
    }

    @Test
    fun `recent routes are distinct, newest first, and filter by code`() {
        fun leg(id: String, o: String, d: String, day: Long) =
            Leg(id, o, d, Instant.ofEpochSecond(day * 86_400), Instant.ofEpochSecond(day * 86_400))
        val legs = listOf(
            leg("1", "EGKB", "LFAC", 1),
            leg("2", "LFAC", "EGKB", 2),
            leg("3", "EGKB", "LFAC", 3),
            leg("4", "EGKB", "", 4),
            leg("5", "LFPB", "LSGS", 5),
        )
        assertEquals(
            listOf("LFPB-LSGS", "EGKB-LFAC", "LFAC-EGKB"),
            RecentRoutes.from(legs).map { "${it.origin}-${it.destination}" },
        )
        assertEquals(Instant.ofEpochSecond(3 * 86_400), RecentRoutes.from(legs)[1].date)
        assertEquals(listOf("LFPB-LSGS"), RecentRoutes.from(legs, "lsg").map { "${it.origin}-${it.destination}" })
    }

    @Test
    fun `timezone table parses and skips junk`() {
        val map = AirportTimezones.parse("EGLL,Europe/London\n\nLFAC,Europe/Paris\nbad\nXXXX,\n")
        assertEquals(mapOf("EGLL" to "Europe/London", "LFAC" to "Europe/Paris"), map)
    }

    @Test
    fun `zone options put UTC first, once, with the offset on the flight's date`() {
        val summer = Instant.parse("2026-07-01T12:00:00Z")
        val winter = Instant.parse("2026-01-01T12:00:00Z")
        assertEquals(
            listOf("UTC", "Paris (UTC+02:00)", "London (UTC+01:00)"),
            ZonedWallClock.timeZoneOptions(listOf("Europe/Paris", "UTC", "Europe/London", "Europe/Paris"), summer).map { it.label },
        )
        assertEquals("London (UTC)", ZonedWallClock.timeZoneOptions(listOf("Europe/London"), winter)[1].label)
    }

    @Test
    fun `the airport's zone replaces the default but never a choice`() {
        val paris = listOf("Europe/Paris")
        assertEquals("Europe/Paris", ZonedWallClock.resolvedTimeZoneId("UTC", paris, "Europe/Paris", chosen = false))
        assertEquals("UTC", ZonedWallClock.resolvedTimeZoneId("UTC", paris, "Europe/Paris", chosen = true))
        assertEquals("UTC", ZonedWallClock.resolvedTimeZoneId("UTC", emptyList(), "Europe/Paris", chosen = false))
        // A zone no longer on the route falls back.
        assertEquals("UTC", ZonedWallClock.resolvedTimeZoneId("Europe/Berlin", paris, null, chosen = true))
    }
}
