package aero.flyfun.forms.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.Instant

/**
 * The weather import: the exchange payload (rzflight
 * `RZFlightFlightExchangeTests`) and how it lands on a new flight (iOS
 * `NewFlightFlow.apply`).
 */
class FlightExchangeTest {

    /** What weather's `flight_to_exchange` emits for a flight with an aircraft the viewer owns. */
    private val weatherExport = """
        {
          "schema_version": 1,
          "route": {
            "departure": "EGTK",
            "destination": "LSGS",
            "alternates": [],
            "waypoints": ["EGTK", "LSGS"],
            "departure_coords": [51.83, -1.32],
            "destination_coords": [46.22, 7.33],
            "alternate_coords": {},
            "waypoint_coords": [],
            "rejected_waypoints": [],
            "aircraft_type": "TBM9",
            "departure_time": "2026-10-03T08:30:00+00:00",
            "arrival_time": "2026-10-03T10:45:00+00:00",
            "flight_level": null,
            "cruise_altitude_ft": 28000
          },
          "name": "Oxford to Sion",
          "source": {"app": "weather", "flight_id": "f-123", "share_code": "abc"},
          "aircraft": {"registration": "N-123AB", "type": "TBM9"}
        }
    """.trimIndent()

    private val t = Instant.parse("2026-09-26T09:00:00Z")
    private val arrival = Instant.parse("2026-09-26T11:15:00Z")

    @Test
    fun `decodes weather's export`() {
        val exchange = FlightExchange.decode(weatherExport)
        assertEquals("EGTK", exchange.route.departure)
        assertEquals("LSGS", exchange.route.destination)
        assertEquals("N-123AB", exchange.aircraft?.registration)
        assertEquals("f-123", exchange.source?.flightId)
        assertEquals(Instant.parse("2026-10-03T08:30:00Z"), ExchangeTime.parse(exchange.route.departureTime))
    }

    @Test
    fun `a minimal payload is enough`() {
        val exchange = FlightExchange.decode("""{"route": {"departure": "EGTF", "destination": "EGLL"}}""")
        assertEquals(1, exchange.schemaVersion)
        assertNull(exchange.aircraft)
    }

    @Test
    fun `refuses a newer schema version`() {
        try {
            FlightExchange.decode("""{"schema_version": 999, "route": {"departure": "EGTF", "destination": "EGLL"}}""")
            fail("A v999 payload must not be read as v1")
        } catch (expected: IllegalArgumentException) {
        }
    }

    @Test
    fun `reads times with an offset, with Z, and without an offset as UTC`() {
        val expected = Instant.parse("2026-10-03T08:30:00Z")
        assertEquals(expected, ExchangeTime.parse("2026-10-03T10:30:00+02:00"))
        assertEquals(expected, ExchangeTime.parse("2026-10-03T08:30:00Z"))
        assertEquals(expected, ExchangeTime.parse("2026-10-03T08:30:00"))
        assertEquals(expected, ExchangeTime.parse("2026-10-03T08:30:00.000000"))
        assertNull(ExchangeTime.parse("tomorrow"))
        assertNull(ExchangeTime.parse(""))
        assertNull(ExchangeTime.parse(null))
    }

    @Test
    fun `applies route, times and aircraft`() {
        val route = ImportedRoute.from(FlightExchange.decode(weatherExport), "", "", t, arrival)
        assertEquals("EGTK", route.origin)
        assertEquals("LSGS", route.destination)
        assertEquals(Instant.parse("2026-10-03T08:30:00Z"), route.departure)
        assertEquals(Instant.parse("2026-10-03T10:45:00Z"), route.arrival)
        assertEquals("N-123AB", route.registration)
        assertEquals("TBM9", route.aircraftType)
    }

    @Test
    fun `an empty endpoint keeps the current one`() {
        val exchange = FlightExchange.decode("""{"route": {"departure": "", "destination": "lfmn"}}""")
        val route = ImportedRoute.from(exchange, "EGTF", "EGLL", t, arrival)
        assertEquals("EGTF", route.origin)
        assertEquals("LFMN", route.destination)
    }

    @Test
    fun `no times keeps the schedule`() {
        val exchange = FlightExchange.decode("""{"route": {"departure": "EGTF", "destination": "LFMN"}}""")
        val route = ImportedRoute.from(exchange, "", "", t, arrival)
        assertEquals(t, route.departure)
        assertEquals(arrival, route.arrival)
        assertNull(route.registration)
    }

    @Test
    fun `a departure without an arrival moves the arrival onto its day`() {
        val exchange = FlightExchange.decode(
            """{"route": {"departure": "EGTF", "destination": "LFMN", "departure_time": "2026-10-03T08:30:00Z"}}""",
        )
        val route = ImportedRoute.from(exchange, "", "", t, arrival)
        assertEquals(Instant.parse("2026-10-03T08:30:00Z"), route.departure)
        assertEquals(Instant.parse("2026-10-03T11:15:00Z"), route.arrival)
    }

    @Test
    fun `the type falls back to the route's`() {
        val exchange = FlightExchange.decode(
            """{"route": {"departure": "EGTF", "destination": "LFMN", "aircraft_type": "SR22"}, "aircraft": {"registration": "G-ABCD"}}""",
        )
        assertEquals("SR22", ImportedRoute.from(exchange, "", "", t, arrival).aircraftType)
    }

    @Test
    fun `registrations match without dashes or case`() {
        assertTrue(ImportedRoute.sameRegistration("G-ABCD", "gabcd"))
        assertTrue(ImportedRoute.sameRegistration("N123AB", "N-123AB"))
        assertFalse(ImportedRoute.sameRegistration("G-ABCD", "G-ABCE"))
    }

    @Test
    fun `lists weather flights newest first, labelled by their endpoints`() {
        val flights = WeatherFlightSummary.decodeList(
            """
            [
              {"id": "a", "route_name": "Old", "waypoints": ["EGTF", "LFAT"], "departure_time": "2026-05-01T09:00:00Z", "extra": 1},
              {"id": "b", "route_name": "Alps", "waypoints": ["EGTK", "LSZH", "LSGS"], "departure_time": "2026-10-03T08:30:00Z"},
              {"id": "c", "route_name": "Draft", "waypoints": ["EGTK"]}
            ]
            """.trimIndent(),
        )
        assertEquals(listOf("b", "a", "c"), flights.map { it.id })
        assertEquals("EGTK → LSGS", flights[0].routeLabel)
        assertEquals("Draft", flights[2].routeLabel)
    }
}
