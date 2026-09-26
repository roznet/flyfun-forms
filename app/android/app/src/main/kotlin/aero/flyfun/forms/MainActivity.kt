package aero.flyfun.forms

import aero.flyfun.forms.auth.AuthService
import aero.flyfun.forms.auth.TokenStore
import aero.flyfun.forms.data.FormFiles
import aero.flyfun.forms.net.ApiClient
import aero.flyfun.forms.net.ApiConfig
import aero.flyfun.forms.ui.AppShortcut
import aero.flyfun.forms.ui.FlyFunApp
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import aero.flyfun.forms.ui.FlyFunTheme
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private lateinit var tokens: TokenStore
    private lateinit var api: ApiClient
    private lateinit var auth: AuthService

    /** A launcher shortcut waiting for the UI to act on it; see res/xml/shortcuts.xml. */
    private val shortcut = MutableStateFlow<AppShortcut?>(null)

    /** The redirect already handled, so a recreated activity does not handle it twice. */
    private var handledCallback: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Target 35+ draws edge to edge regardless; this also makes the system
        // bar icons follow the theme, light or dark.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        tokens = TokenStore(this)
        api = ApiClient(tokens)
        auth = AuthService(this, api, tokens)

        // Forms left from an earlier run carry passport data; nothing can
        // still be reading them now. See FormFiles.
        if (!purgedThisProcess) {
            purgedThisProcess = true
            FormFiles.purge(cacheDir)
        }

        setContent {
            FlyFunTheme {
                FlyFunApp(auth = auth, tokens = tokens, api = api, shortcut = shortcut)
            }
        }
        handledCallback = savedInstanceState?.getString(KEY_HANDLED_CALLBACK)
        handleAuthRedirect(intent)
        // Only on a fresh start: a recreated activity keeps its old intent,
        // and the shortcut was acted on the first time.
        if (savedInstanceState == null) shortcut.value = AppShortcut.from(intent?.action)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString(KEY_HANDLED_CALLBACK, handledCallback)
    }

    override fun onResume() {
        super.onResume()
        // Back from a share: whatever took the file has had time to read it.
        FormFiles.purge(cacheDir, olderThan = FormFiles.SHARE_GRACE)
    }

    /**
     * The activity is singleTask, so the OAuth redirect arrives here rather
     * than starting a second copy on top of the running task.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAuthRedirect(intent)
        AppShortcut.from(intent.action)?.let { shortcut.value = it }
    }

    private companion object {
        var purgedThisProcess = false
        const val KEY_HANDLED_CALLBACK = "handled_auth_callback"
    }

    private fun handleAuthRedirect(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme != ApiConfig.CALLBACK_SCHEME) return
        // Not again on rotation: the nonce is spent, and a second pass would
        // report a sign-in that just worked as failed.
        if (uri.toString() == handledCallback) return
        handledCallback = uri.toString()
        lifecycleScope.launch {
            // Success needs nothing here: the UI observes TokenStore.signedIn.
            auth.handleCallback(uri)
                .onFailure {
                    Toast.makeText(
                        this@MainActivity,
                        it.message ?: getString(R.string.app_sign_in_failed),
                        Toast.LENGTH_LONG,
                    ).show()
                }
        }
    }
}
