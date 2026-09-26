package aero.flyfun.forms.ui.webform

import aero.flyfun.forms.net.FillPlan
import android.annotation.SuppressLint
import android.content.Context
import android.webkit.CookieManager
import android.webkit.WebStorage
import android.webkit.WebView
import androidx.activity.compose.BackHandler
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

/**
 * An airport's own web form (book-out, PPR, out-of-hours), opened prefilled.
 *
 * The server returns a [FillPlan] from /prefill; this page applies it and then
 * gets out of the way. **The pilot submits on the page - the app never does.**
 * Submitting someone else's form on their behalf is not a thing to automate.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WebFormScreen(plan: FillPlan, onBack: () -> Unit) {
    var status by remember { mutableStateOf<String?>(null) }
    var webView by remember { mutableStateOf<WebView?>(null) }

    // Back walks the page's own history first (a multi-step form, its
    // confirmation page), and only leaves once there is nothing to go back to.
    BackHandler {
        val view = webView
        if (view != null && view.canGoBack()) view.goBack() else onBack()
    }

    // iOS gives each web form a non-persistent store. The WebView's cookie jar
    // and storage are app-wide and on disk, so clear them on the way out:
    // these pages hold the pilot's name, passport and phone number.
    DisposableEffect(Unit) {
        onDispose {
            webView?.apply {
                stopLoading()
                clearHistory()
                clearCache(true)
            }
            clearCookiesAndStorage()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(plan.label) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    TextButton(onClick = {
                        webView?.let { status = null; it.applyPlan(plan) { s -> status = s } }
                    }) { Text("Fill again") }
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            plan.note?.let { note ->
                Card(Modifier.fillMaxWidth().padding(8.dp)) {
                    Text(note, Modifier.padding(12.dp), style = MaterialTheme.typography.bodySmall)
                }
            }
            status?.let {
                Card(Modifier.fillMaxWidth().padding(horizontal = 8.dp)) {
                    Text(it, Modifier.padding(12.dp), style = MaterialTheme.typography.bodySmall)
                }
            }
            Text(
                "Check the details, then submit on the page itself.",
                Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
                style = MaterialTheme.typography.labelSmall,
            )
            Box(Modifier.fillMaxSize()) {
                AndroidView(
                    modifier = Modifier.fillMaxSize(),
                    factory = { ctx ->
                        @SuppressLint("SetJavaScriptEnabled")
                        WebView(ctx).apply {
                            settings.javaScriptEnabled = true
                            settings.domStorageEnabled = true
                            var filledOnce = false
                            webViewClient = object : WebViewClient() {
                                override fun onPageFinished(view: WebView, url: String) {
                                    // Only after the FIRST load. Submitting a
                                    // RedAtlas form loads a confirmation page,
                                    // and refilling that would be wrong.
                                    if (filledOnce) return
                                    filledOnce = true
                                    view.applyPlan(plan) { status = it }
                                }
                            }
                            loadUrl(plan.url)
                            webView = this
                        }
                    },
                )
            }
        }
    }
}

private fun clearCookiesAndStorage() {
    CookieManager.getInstance().apply {
        removeAllCookies(null)
        flush()
    }
    WebStorage.getInstance().deleteAllData()
}

/**
 * Everything a web form can have left on disk, for "Delete all data". Normally
 * already empty - leaving a form clears it - but a crash or process death
 * while one is open skips that.
 *
 * The HTTP cache is app-wide, but clearing it needs a WebView instance, so a
 * throwaway one is made. Main thread only.
 */
fun clearWebFormStorage(context: Context) {
    clearCookiesAndStorage()
    WebView(context).apply {
        clearCache(true)
        destroy()
    }
}

private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

/**
 * Applies the plan by injecting the same script the iOS app uses - the
 * JavaScript is genuinely identical, which is why this was the cheapest port in
 * the project.
 */
private fun WebView.applyPlan(plan: FillPlan, onStatus: (String) -> Unit) {
    val planJson = json.encodeToString(FillPlan.serializer(), plan)
    evaluateJavascript("($FILL_SCRIPT)($planJson)") { raw ->
        val result = runCatching {
            // evaluateJavascript hands back a JSON-encoded string, so the
            // payload is double-encoded.
            val inner = json.decodeFromString(String.serializer(), raw)
            json.decodeFromString(FillOutcome.serializer(), inner)
        }.getOrNull()

        onStatus(
            when {
                result == null -> "Could not fill this page automatically."
                result.missing.isEmpty() -> "Filled ${result.filled.size} fields."
                else -> "Filled ${result.filled.size} fields. Not found: ${result.missing.joinToString(", ")}"
            },
        )
    }
}

@kotlinx.serialization.Serializable
private data class FillOutcome(
    val filled: List<String> = emptyList(),
    val missing: List<String> = emptyList(),
)

/**
 * Verbatim from `Views/WebFormView.swift`. Kept byte-identical deliberately:
 * these pages are fragile third-party forms, and two diverging copies of this
 * script would be two sets of bugs.
 */
private const val FILL_SCRIPT = """
function (plan) {
  const root = plan.scope ? document.querySelector(plan.scope) : document;
  if (!root) {
    return JSON.stringify({ filled: [], missing: plan.fields.map(f => f.name) });
  }
  const filled = [];
  const missing = [];
  for (const field of plan.fields) {
    const el = root.querySelector('[name="' + CSS.escape(field.name) + '"]');
    if (!el) {
      missing.push(field.name);
      continue;
    }
    if (field.type === "checkbox") {
      // Click rather than set, so the page's own handlers run (RedAtlas
      // enables its return fields from the checkbox's click handler).
      if (el.checked !== (field.value === "true")) { el.click(); }
    } else {
      // The prototype's setter, so pages that track input values see it
      const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), "value")?.set;
      if (setter) { setter.call(el, field.value); } else { el.value = field.value; }
      // Date/time pickers (Elementor uses flatpickr) keep their own state
      if (el._flatpickr) { el._flatpickr.setDate(field.value, false); }
      // So does RedAtlas's autocomplete (autocomplete.js on jQuery)
      if (window.jQuery && window.jQuery(el).data("aaAutocomplete")) {
        window.jQuery(el).autocomplete("val", field.value);
      }
      el.dispatchEvent(new Event("input", { bubbles: true }));
      el.dispatchEvent(new Event("change", { bubbles: true }));
    }
    filled.push(field.name);
  }
  if (root !== document) { root.scrollIntoView({ behavior: "smooth", block: "start" }); }
  return JSON.stringify({ filled: filled, missing: missing });
}
"""
