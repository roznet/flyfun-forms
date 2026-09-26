package aero.flyfun.forms.scan

import aero.flyfun.forms.logic.MRZParser
import aero.flyfun.forms.logic.MRZScanResult
import android.annotation.SuppressLint
import android.content.Context
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

/**
 * Turns camera frames into a parsed MRZ.
 *
 * ML Kit replaces Vision as the OCR; the parsing itself is the ported
 * [MRZParser] in :core-logic, unchanged and already covered by 20 tests. This
 * class is only the glue, which is deliberate - the part that is hard to get
 * right is the part that does not depend on a camera.
 *
 * Starts ML Kit itself ([startMlKit]): it is not started at app launch.
 */
class MrzScanner(
    context: Context,
    private val onResult: (MRZScanResult) -> Unit,
) : ImageAnalysis.Analyzer {

    private val recognizer = run {
        startMlKit(context)
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    /** Stop once a frame parses; a passport does not change mid-scan. */
    @Volatile
    private var done = false

    @SuppressLint("UnsafeOptInUsageError")
    override fun analyze(imageProxy: ImageProxy) {
        val media = imageProxy.image
        if (done || media == null) {
            imageProxy.close()
            return
        }
        val image = InputImage.fromMediaImage(media, imageProxy.imageInfo.rotationDegrees)
        recognizer.process(image)
            .addOnSuccessListener { text ->
                candidateLines(text.text)?.let { lines ->
                    MRZParser.parse(lines)?.let { result ->
                        if (!done) {
                            done = true
                            onResult(result)
                        }
                    }
                }
            }
            .addOnCompleteListener { imageProxy.close() }
    }

    fun reset() { done = false }

    companion object {
        /**
         * Pick the MRZ lines out of whatever OCR returned.
         *
         * A passport page carries plenty of other text, so candidates are lines
         * of the right length made only of MRZ characters. TD3 is two lines of
         * 44, TD1 three of 30.
         *
         * OCR frequently drops or adds a character, so lines are padded or
         * trimmed to the exact width before parsing - the check digits will
         * reject a genuinely bad read, which is a better filter than length.
         */
        fun candidateLines(raw: String): List<String>? {
            val cleaned = raw.lines()
                .map { it.replace(" ", "").replace("«", "<").uppercase() }
                .filter { it.isNotEmpty() && it.all { c -> c.isLetterOrDigit() || c == '<' } }

            fun fit(line: String, width: Int) =
                if (line.length >= width) line.take(width) else line.padEnd(width, '<')

            val td3 = cleaned.filter { it.length in 40..46 }
            if (td3.size >= 2) {
                val last = td3.takeLast(2)
                return last.map { fit(it, 44) }
            }
            val td1 = cleaned.filter { it.length in 27..33 }
            if (td1.size >= 3) {
                val last = td1.takeLast(3)
                return last.map { fit(it, 30) }
            }
            return null
        }
    }
}
