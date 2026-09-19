package aero.flyfun.forms.logic

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.Instant

/**
 * Ported from `FlyFunCommonTests/ZonedWallClockTests.swift`.
 *
 * The DST cases are the reason this type exists, so they are asserted against
 * real European transition dates rather than a synthetic zone.
 */
class ZonedWallClockTest {

    private val paris = "Europe/Paris"

    @Test
    fun `reads the instant in the selected zone`() {
        val c = ZonedWallClock(Instant.parse("2026-07-01T10:00:00Z"), paris)
        assertEquals(12, c.hour) // summer: UTC+2
        assertEquals(1, c.day)
    }

    @Test
    fun `winter and summer resolve different offsets with no special casing`() {
        val summer = ZonedWallClock(Instant.parse("2026-07-01T10:00:00Z"), paris)
        val winter = ZonedWallClock(Instant.parse("2026-01-01T10:00:00Z"), paris)
        assertEquals(12, summer.hour)
        assertEquals(11, winter.hour)
    }

    @Test
    fun `switching zone preserves the instant and re-displays it`() {
        val utc = ZonedWallClock(Instant.parse("2026-07-01T10:00:00Z"))
        val inParis = utc.settingZone(paris)
        assertEquals(utc.instant, inParis.instant)
        assertEquals(10, utc.hour)
        assertEquals(12, inParis.hour)
    }

    @Test
    fun `an hour edit stays on the displayed day and carries the date into the instant`() {
        // 23:30 Paris on the 1st. Setting the hour to 00 means 00:30 on the
        // *same displayed day* - Swift's settingHour is documented as "on the
        // same displayed day". What must not happen is the date being dropped:
        // 00:30 Paris on 1 July is 22:30Z on 30 June, so the UTC day differs
        // from the local one. A picker that wrote only HH:mm into a fixed date
        // would get this wrong, which is the bug the type exists to remove.
        val c = ZonedWallClock(Instant.parse("2026-07-01T21:30:00Z"), paris)
        assertEquals(23, c.hour)
        assertEquals(1, c.day)

        val moved = c.settingHour(0)
        assertEquals(0, moved.hour)
        assertEquals(1, moved.day)
        assertEquals(Instant.parse("2026-06-30T22:30:00Z"), moved.instant)
    }

    @Test
    fun `a date edit moves the day and the instant follows`() {
        val c = ZonedWallClock(Instant.parse("2026-07-01T21:30:00Z"), paris)
        val next = c.settingDate(2026, 7, 2)
        assertEquals(2, next.day)
        assertEquals(23, next.hour)
        assertEquals(Instant.parse("2026-07-02T21:30:00Z"), next.instant)
    }

    @Test
    fun `editing the date keeps the displayed time of day`() {
        val c = ZonedWallClock(Instant.parse("2026-07-01T10:00:00Z"), paris)
        val moved = c.settingDate(2026, 12, 24)
        assertEquals(12, moved.hour) // wall clock preserved...
        assertEquals(24, moved.day)
        // ...and because December is CET, the underlying instant shifts by an hour
        assertEquals(Instant.parse("2026-12-24T11:00:00Z"), moved.instant)
    }

    @Test
    fun `spring-forward gap resolves onto the transition rather than failing`() {
        // Paris skips 02:00-03:00 on 2026-03-29.
        val c = ZonedWallClock(Instant.parse("2026-03-29T00:30:00Z"), paris) // 01:30 CET
        assertEquals(1, c.hour)
        val edited = c.settingHour(2) // 02:30 does not exist that night
        // java.time shifts a gap wall-clock forward by the length of the gap,
        // so 02:30 CET becomes 03:30 CEST. Swift's Calendar resolves it the
        // same way. The point is that it resolves rather than failing.
        assertEquals(3, edited.hour)
        assertEquals(30, edited.minute)
        assertEquals(Instant.parse("2026-03-29T01:30:00Z"), edited.instant)
    }

    @Test
    fun `autumn overlap keeps the occurrence being displayed`() {
        // Paris repeats 02:00-03:00 on 2026-10-25. 00:30Z is the second pass
        // (02:30 CET, +01:00); 23:30Z the previous day would be the first.
        val secondPass = ZonedWallClock(Instant.parse("2026-10-25T01:30:00Z"), paris)
        assertEquals(2, secondPass.hour)

        val edited = secondPass.settingMinute(45)
        assertEquals(2, edited.hour)
        // Must stay on the second occurrence, not jump back an hour to the first
        assertEquals(Instant.parse("2026-10-25T01:45:00Z"), edited.instant)
    }

    @Test
    fun `first pass of the repeated hour stays on the first pass`() {
        val firstPass = ZonedWallClock(Instant.parse("2026-10-25T00:30:00Z"), paris)
        assertEquals(2, firstPass.hour)
        val edited = firstPass.settingMinute(45)
        assertEquals(Instant.parse("2026-10-25T00:45:00Z"), edited.instant)
    }

    @Test
    fun `an unknown zone degrades to UTC instead of throwing`() {
        val c = ZonedWallClock(Instant.parse("2026-07-01T10:00:00Z"), "Not/AZone")
        assertEquals(10, c.hour)
    }

    @Test
    fun `minute options and snapping`() {
        assertEquals(listOf(0, 15, 30, 45), ZonedWallClock.minuteOptions(15))
        assertEquals(listOf(0, 30), ZonedWallClock.minuteOptions(30))
        assertEquals(30, ZonedWallClock.nearestMinuteOption(37, 15))
        assertEquals(0, ZonedWallClock.nearestMinuteOption(2, 15))
        // A minute in the final gap snaps down, staying inside the hour
        assertEquals(45, ZonedWallClock.nearestMinuteOption(59, 15))
    }

    @Test
    fun `step is clamped rather than rejected`() {
        assertEquals(60, ZonedWallClock.minuteOptions(0).size)
        assertEquals(listOf(0), ZonedWallClock.minuteOptions(90))
    }
}
