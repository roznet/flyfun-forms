package aero.flyfun.forms.scan

import android.content.Context
import com.google.mlkit.common.MlKit

/**
 * Starts ML Kit, once per process. Every path that uses ML Kit must call this
 * first.
 *
 * ML Kit normally starts itself at app launch through its `MlKitInitProvider`,
 * and once running it sends Google usage metrics (PRIVACY.md, legal/GDPR.md
 * §6a). The manifest removes that provider so a pilot who never scans never
 * runs ML Kit; the price is that anything calling ML Kit without this first
 * fails with "MlKitContext has not been initialized".
 *
 * The guard is ours because `MlKit.initialize` is **not** idempotent: a second
 * call throws "MlKitContext is already initialized" - which is what opening
 * the scanner a second time would do without it.
 */
private val lock = Any()

@Volatile
private var started = false

fun startMlKit(context: Context) {
    if (started) return
    synchronized(lock) {
        if (started) return
        MlKit.initialize(context.applicationContext)
        started = true
    }
}
