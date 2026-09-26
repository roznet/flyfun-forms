package aero.flyfun.forms.scan

import aero.flyfun.forms.logic.MRZParser
import aero.flyfun.forms.logic.MRZScanResult
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

/**
 * Reads the MRZ off a photo or a PDF the pilot picked, rather than the camera.
 * Port of iOS `ImageOCRManager`: a PDF is rendered page by page at about 300
 * dpi on white until one parses.
 *
 * Nothing is kept: the picked file is read through its content URI and the
 * rendered pages live only in memory.
 */
object ImageMrzReader {

    /** The first MRZ found, or null when there is none to read. */
    suspend fun read(context: Context, uri: Uri, isPdf: Boolean): MRZScanResult? =
        if (isPdf) readPdf(context, uri) else readImage(context, uri)

    private suspend fun readImage(context: Context, uri: Uri): MRZScanResult? {
        // fromFilePath applies the photo's EXIF rotation, which a passport
        // photographed sideways depends on.
        val image = withContext(Dispatchers.IO) { runCatching { InputImage.fromFilePath(context, uri) }.getOrNull() }
            ?: return null
        return recognise(image)
    }

    private suspend fun readPdf(context: Context, uri: Uri): MRZScanResult? {
        val descriptor = withContext(Dispatchers.IO) {
            runCatching { context.contentResolver.openFileDescriptor(uri, "r") }.getOrNull()
        } ?: return null
        descriptor.use { fd ->
            val renderer = withContext(Dispatchers.IO) { runCatching { PdfRenderer(fd) }.getOrNull() } ?: return null
            renderer.use {
                // A scanned passport is a page or two; a long PDF is not worth reading to the end.
                for (index in 0 until minOf(renderer.pageCount, MAX_PAGES)) {
                    val bitmap = withContext(Dispatchers.IO) { renderPage(renderer, index) }
                    val result = recognise(InputImage.fromBitmap(bitmap, 0))
                    bitmap.recycle()
                    if (result != null) return result
                }
            }
        }
        return null
    }

    private fun renderPage(renderer: PdfRenderer, index: Int): Bitmap {
        renderer.openPage(index).use { page ->
            // 300 dpi from the page's 72-dpi points, capped so a poster-sized
            // page does not exhaust memory.
            val scale = minOf(300f / 72f, MAX_SIDE / maxOf(page.width, page.height).toFloat())
            val bitmap = Bitmap.createBitmap(
                (page.width * scale).toInt().coerceAtLeast(1),
                (page.height * scale).toInt().coerceAtLeast(1),
                Bitmap.Config.ARGB_8888,
            )
            // PDF pages are transparent; OCR wants dark text on white.
            bitmap.eraseColor(Color.WHITE)
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            return bitmap
        }
    }

    private suspend fun recognise(image: InputImage): MRZScanResult? = suspendCancellableCoroutine { cont ->
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        recognizer.process(image)
            .addOnSuccessListener { text ->
                val result = MrzScanner.candidateLines(text.text)?.let { MRZParser.parse(it) }
                recognizer.close()
                if (cont.isActive) cont.resume(result)
            }
            .addOnFailureListener {
                recognizer.close()
                if (cont.isActive) cont.resume(null)
            }
    }

    private const val MAX_PAGES = 5
    private const val MAX_SIDE = 3000f
}
