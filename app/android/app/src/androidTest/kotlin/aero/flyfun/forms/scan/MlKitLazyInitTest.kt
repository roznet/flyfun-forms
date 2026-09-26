package aero.flyfun.forms.scan

import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.mlkit.common.sdkinternal.MlKitContext
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith

/**
 * ML Kit sends Google usage metrics once running (PRIVACY.md), so it must not
 * start with the app - only when the pilot scans.
 *
 * The instrumentation process starts the app's Application and content
 * providers exactly as a launch does, so if `MlKitInitProvider` crept back into
 * the merged manifest (a dependency bump, a lost `tools:node="remove"`), ML Kit
 * would already be initialised when this runs.
 *
 * One test, in order: once started, ML Kit stays up for the rest of the
 * process, so only the first entry point can be shown to start it. That is the
 * photo/PDF reader, the path that does not construct [MrzScanner]; the camera
 * scanner then only has to construct without crashing. Both call [startMlKit].
 *
 * Each path runs twice, as a pilot scanning a second passport does:
 * `MlKit.initialize` throws on a second call, so a guard that stopped working
 * would crash the second scan.
 */
@RunWith(AndroidJUnit4::class)
class MlKitLazyInitTest {

    @Test
    fun ml_kit_starts_with_a_scan_not_with_the_app() = runTest {
        assertThrows(IllegalStateException::class.java) { MlKitContext.getInstance() }

        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val missing = Uri.parse("content://aero.flyfun.forms.fileprovider/none/missing.jpg")
        assertNull(ImageMrzReader.read(ctx, missing, isPdf = false))
        MlKitContext.getInstance() // throws if the reader did not start it
        assertNull(ImageMrzReader.read(ctx, missing, isPdf = true))

        MrzScanner(ctx) {}
        MrzScanner(ctx) {}
    }
}
