package aero.flyfun.forms.data

import java.io.File
import java.time.Duration
import java.time.Instant

/**
 * Where generated forms and data exports are written before they are shared,
 * and how they are cleared.
 *
 * These files carry passport numbers, so they must not sit in the cache until
 * the system gets round to evicting it. A file cannot be deleted the moment it
 * is handed to another app - the mail app reads it after our share intent has
 * returned, sometimes much later if the pilot leaves the draft open - so they
 * go on the next start, and on returning to the app once a share has had
 * [SHARE_GRACE] to be read.
 */
object FormFiles {

    val SHARE_GRACE: Duration = Duration.ofMinutes(15)

    fun dir(cacheDir: File): File = File(cacheDir, "forms").apply { mkdirs() }

    /** Delete every file last written more than [olderThan] ago; [Duration.ZERO] clears them all. */
    fun purge(cacheDir: File, olderThan: Duration = Duration.ZERO, now: Instant = Instant.now()) {
        val cutoff = now.minus(olderThan).toEpochMilli()
        File(cacheDir, "forms").listFiles()
            ?.filter { it.isFile && it.lastModified() <= cutoff }
            ?.forEach { it.delete() }
    }
}
