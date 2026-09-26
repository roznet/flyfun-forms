package aero.flyfun.forms.logic

import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

/**
 * A timezone-aware wall clock over an absolute instant.
 *
 * Port of `FlyFunCommon/DateTime/ZonedWallClock.swift`.
 *
 * [instant] is the single source of truth. The wall clock is *derived* by
 * reading it in [zoneId], and every edit rebuilds the instant from the wall
 * clock interpreted in that same zone. Two behaviours fall out, and they are
 * the point of the type:
 *
 *  - Switching zone preserves the instant and re-displays it, rather than
 *    reinterpreting the digits on screen as a different moment.
 *  - Editing is DST-correct for the *displayed* date rather than for today, so
 *    a summer Europe/Paris is +02:00 and a winter one +01:00 with no special
 *    casing.
 *
 * Rebuilds carry the full date, so a time edit that crosses midnight in the
 * selected zone moves the day instead of wrapping inside it. A picker built on
 * a fixed offset and a bare HH:mm cannot express that, which is the class of
 * bug this type exists to remove.
 */
/** A zone a picker offers, and how it reads. */
data class ZoneOption(val identifier: String, val label: String)

data class ZonedWallClock(
    val instant: Instant,
    val zoneId: String = UTC,
) {
    companion object {
        const val UTC = "UTC"

        /** The minute values a picker of [step] offers, e.g. [0, 15, 30, 45]. */
        fun minuteOptions(step: Int): List<Int> {
            val s = step.coerceIn(1, 60)
            return (0 until 60 step s).toList()
        }

        /**
         * The option of [step] closest to [minute].
         *
         * Candidates stop below 60, so a minute in the final gap snaps down to
         * the last option rather than up to the next hour - a picker selection
         * has to stay inside the displayed hour.
         */
        fun nearestMinuteOption(minute: Int, step: Int): Int =
            minuteOptions(step).minByOrNull { kotlin.math.abs(it - minute) } ?: 0

        /**
         * The zones a schedule field offers: UTC, then each airport's zone in
         * route order, once each, labelled with its offset on the flight's
         * own date so DST reads right.
         */
        fun timeZoneOptions(available: List<String>, at: Instant): List<ZoneOption> =
            (listOf(UTC) + available).distinct().map { id ->
                if (id == UTC) {
                    ZoneOption(UTC, "UTC")
                } else {
                    val offset = runCatching { ZoneId.of(id).rules.getOffset(at) }.getOrNull()
                    val city = id.substringAfterLast('/').replace('_', ' ')
                    ZoneOption(id, if (offset == null) city else "$city (UTC${offset.id.replace("Z", "")})")
                }
            }

        /**
         * The zone to show: the pilot's own choice while it is still on
         * offer; otherwise the [preferred] airport's zone once it is known;
         * otherwise UTC. [chosen] is false until the pilot picks one, so a
         * zone arriving later takes over from the default but never from a
         * choice.
         */
        fun resolvedTimeZoneId(current: String, available: List<String>, preferred: String?, chosen: Boolean): String {
            val offered = listOf(UTC) + available
            if (chosen && current in offered) return current
            return preferred?.takeIf { it in available } ?: current.takeIf { it in offered } ?: UTC
        }
    }

    /** An unknown identifier degrades to UTC rather than throwing, so a stale stored zone stays readable. */
    val zone: ZoneId
        get() = runCatching { ZoneId.of(zoneId) }.getOrDefault(ZoneId.of(UTC))

    private val zoned: ZonedDateTime get() = instant.atZone(zone)

    val year: Int get() = zoned.year
    val month: Int get() = zoned.monthValue
    val day: Int get() = zoned.dayOfMonth
    val hour: Int get() = zoned.hour
    val minute: Int get() = zoned.minute

    /** The wall-clock minute snapped to the nearest option a picker of [step] offers. */
    fun minuteOption(step: Int): Int = nearestMinuteOption(minute, step)

    fun settingHour(newHour: Int): ZonedWallClock = rebuild(hour = newHour)

    fun settingMinute(newMinute: Int): ZonedWallClock = rebuild(minute = newMinute)

    fun settingDate(year: Int, month: Int, day: Int): ZonedWallClock =
        rebuild(year = year, month = month, day = day)

    /**
     * Display the same moment in another zone.
     *
     * The instant is deliberately unchanged: the pilot is re-expressing a time
     * they already chose, not moving the flight.
     */
    fun settingZone(identifier: String): ZonedWallClock = copy(zoneId = identifier)

    fun format(pattern: String): String =
        DateTimeFormatter.ofPattern(pattern).format(zoned)

    /**
     * Rebuild the instant from the current wall clock with the given overrides.
     *
     * The full set of fields is carried, so the date moves with the time when an
     * edit crosses midnight and the offset is resolved for the resulting date.
     *
     * DST, both directions:
     *  - A wall clock in the spring-forward gap does not exist. `atZone` shifts
     *    it forward onto the transition, which is what Swift's Calendar does.
     *  - A wall clock in the autumn overlap happens twice, and `atZone` always
     *    picks the earlier offset. An edit made while displaying the *second*
     *    occurrence would jump an hour back, so when the original instant was at
     *    the later offset we keep that occurrence.
     */
    private fun rebuild(
        year: Int? = null,
        month: Int? = null,
        day: Int? = null,
        hour: Int? = null,
        minute: Int? = null,
    ): ZonedWallClock {
        val current = zoned
        val local = LocalDateTime.of(
            year ?: current.year,
            month ?: current.monthValue,
            day ?: current.dayOfMonth,
            hour ?: current.hour,
            minute ?: current.minute,
            0,
        )
        var rebuilt = local.atZone(zone)
        if (rebuilt.offset != current.offset) {
            val later = rebuilt.withLaterOffsetAtOverlap()
            if (later.offset == current.offset) rebuilt = later
        }
        return copy(instant = rebuilt.toInstant())
    }
}
