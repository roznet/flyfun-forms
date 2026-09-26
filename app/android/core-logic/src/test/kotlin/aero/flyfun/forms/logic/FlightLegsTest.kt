package aero.flyfun.forms.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant

class FlightLegsTest {

    private fun leg(id: String, from: String, to: String, day: Int, hour: Int = 9) = Leg(
        id = id,
        origin = from,
        destination = to,
        departure = Instant.parse("2026-10-%02dT%02d:00:00Z".format(day, hour)),
        arrival = Instant.parse("2026-10-%02dT%02d:00:00Z".format(day, hour + 2)),
    )

    private val out = leg("out", "EGTF", "LFAC", day = 10)

    @Test
    fun `arriving, the connection is the next departure from that airport`() {
        val onward = leg("onward", "LFAC", "LFRM", day = 12)
        val later = leg("later", "LFAC", "LSGS", day = 15)
        val elsewhere = leg("elsewhere", "EGTF", "EGKA", day = 11)
        assertEquals(onward, FlightLegs.connecting(out, "LFAC", listOf(later, elsewhere, onward, out)))
    }

    @Test
    fun `leaving, the connection is the previous arrival at that airport`() {
        val earlier = leg("earlier", "EGKA", "EGTF", day = 2)
        val inbound = leg("inbound", "EGLL", "EGTF", day = 8)
        assertEquals(inbound, FlightLegs.connecting(out, "egtf", listOf(earlier, inbound, out)))
    }

    @Test
    fun `nothing connects beyond two weeks`() {
        val tooLate = leg("late", "LFAC", "LFRM", day = 25)
        assertNull(FlightLegs.connecting(out, "LFAC", listOf(tooLate)))
    }

    @Test
    fun `the flight never connects with itself`() {
        assertNull(FlightLegs.connecting(out, "LFAC", listOf(out)))
    }

    @Test
    fun `a local flight connects as an arrival`() {
        val local = leg("local", "LFAC", "LFAC", day = 10)
        val before = leg("before", "EGTF", "LFAC", day = 9)
        val after = leg("after", "LFAC", "EGTF", day = 11)
        assertEquals(after, FlightLegs.connecting(local, "LFAC", listOf(before, after)))
    }

    @Test
    fun `the return is the first later landing back at the departure airport`() {
        val hop = leg("hop", "LFAC", "LFRM", day = 12)
        val back = leg("back", "LFRM", "EGTF", day = 14)
        val backAgain = leg("again", "LFAC", "EGTF", day = 20)
        assertEquals(back, FlightLegs.returning(out, "EGTF", listOf(backAgain, hop, back, out)))
    }

    @Test
    fun `only the departure airport has a return`() {
        val back = leg("back", "LFAC", "EGTF", day = 12)
        assertNull(FlightLegs.returning(out, "LFAC", listOf(back)))
    }

    @Test
    fun `a local flight is its own return`() {
        val local = leg("local", "EGTF", "EGTF", day = 10)
        assertEquals(local, FlightLegs.returning(local, "EGTF", emptyList()))
    }

    @Test
    fun `no return within two weeks is no return`() {
        val muchLater = leg("later", "LFAC", "EGTF", day = 30)
        assertNull(FlightLegs.returning(out, "EGTF", listOf(muchLater)))
    }
}
