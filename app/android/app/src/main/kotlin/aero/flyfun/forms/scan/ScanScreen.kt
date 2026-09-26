package aero.flyfun.forms.scan

import aero.flyfun.forms.logic.MRZScanResult
import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.activity.result.PickVisualMediaRequest
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.TextButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.PictureAsPdf
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import kotlinx.coroutines.launch
import java.util.concurrent.Executors

/**
 * Point the camera at the two lines at the bottom of a passport, or pick a
 * photo or PDF of the page.
 *
 * Nothing is stored: frames are analysed in memory and discarded, and only the
 * parsed fields reach the caller. A passport photo on disk would be a far worse
 * liability than the text it contains.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScanScreen(onScanned: (MRZScanResult) -> Unit, onBack: () -> Unit) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    var reading by remember { mutableStateOf(false) }
    var notFound by remember { mutableStateOf(false) }
    var sourceMenu by remember { mutableStateOf(false) }

    fun readFile(uri: android.net.Uri?, isPdf: Boolean) {
        uri ?: return
        scope.launch {
            reading = true
            notFound = false
            val result = ImageMrzReader.read(context, uri, isPdf)
            reading = false
            if (result == null) notFound = true else onScanned(result)
        }
    }
    // The Photo Picker needs no permission; a PDF comes through SAF.
    val photo = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { readFile(it, isPdf = false) }
    val pdf = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { readFile(it, isPdf = true) }

    var granted by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }
    val request = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        granted = it
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Scan document") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    Box {
                        IconButton(onClick = { sourceMenu = true }, enabled = !reading) {
                            Icon(Icons.Default.PhotoLibrary, contentDescription = "Scan from a photo or PDF")
                        }
                        DropdownMenu(expanded = sourceMenu, onDismissRequest = { sourceMenu = false }) {
                            DropdownMenuItem(
                                text = { Text("Choose Photo") },
                                leadingIcon = { Icon(Icons.Default.Image, contentDescription = null) },
                                onClick = {
                                    sourceMenu = false
                                    photo.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("Choose PDF") },
                                leadingIcon = { Icon(Icons.Default.PictureAsPdf, contentDescription = null) },
                                onClick = { sourceMenu = false; pdf.launch(arrayOf("application/pdf")) },
                            )
                        }
                    }
                },
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            if (!granted) {
                Column(
                    Modifier.fillMaxSize().padding(32.dp),
                    Arrangement.Center,
                    Alignment.CenterHorizontally,
                ) {
                    Text("Camera access", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Used only to read the two lines at the bottom of a passport. " +
                            "No image is saved.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Button(
                        onClick = { request.launch(Manifest.permission.CAMERA) },
                        modifier = Modifier.padding(top = 12.dp),
                    ) { Text("Allow camera") }
                }
            } else {
                CameraPreview(onScanned)
                Text(
                    "Line up the two lines at the bottom of the passport or ID card",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(24.dp),
                )
            }
            if (reading) CircularProgressIndicator(Modifier.align(Alignment.Center))
        }
    }

    if (notFound) {
        AlertDialog(
            onDismissRequest = { notFound = false },
            title = { Text("No Document Found") },
            text = {
                Text(
                    "No machine-readable zone (MRZ) was found in the file. " +
                        "Try a clearer image or PDF of the passport page.",
                )
            },
            confirmButton = { TextButton(onClick = { notFound = false }) { Text("OK") } },
        )
    }

    // Nothing to dispose when permission was never granted; the camera binding
    // below owns its own lifecycle.
    DisposableEffect(lifecycleOwner) { onDispose { } }
}

@Composable
private fun CameraPreview(onScanned: (MRZScanResult) -> Unit) {
    // The analyser is built once; this keeps it calling the current callback.
    val latestCallback by androidx.compose.runtime.rememberUpdatedState(onScanned)
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val executor = remember { Executors.newSingleThreadExecutor() }

    DisposableEffect(Unit) { onDispose { executor.shutdown() } }

    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { ctx ->
            val previewView = PreviewView(ctx)
            val providerFuture = ProcessCameraProvider.getInstance(ctx)
            providerFuture.addListener({
                val provider = providerFuture.get()
                val preview = Preview.Builder().build().also {
                    it.surfaceProvider = previewView.surfaceProvider
                }
                val analysis = ImageAnalysis.Builder()
                    // Only the newest frame matters; a backlog would make the
                    // scanner feel laggy and change nothing about the result.
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                    .also { it.setAnalyzer(executor, MrzScanner(ctx) { result -> latestCallback(result) }) }

                provider.unbindAll()
                provider.bindToLifecycle(
                    lifecycleOwner,
                    CameraSelector.DEFAULT_BACK_CAMERA,
                    preview,
                    analysis,
                )
            }, ContextCompat.getMainExecutor(ctx))
            previewView
        },
    )
}
