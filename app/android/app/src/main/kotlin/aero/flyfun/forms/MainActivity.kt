package aero.flyfun.forms

import aero.flyfun.forms.auth.AuthService
import aero.flyfun.forms.auth.TokenStore
import aero.flyfun.forms.net.ApiClient
import aero.flyfun.forms.net.ApiConfig
import aero.flyfun.forms.ui.FlyFunApp
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private lateinit var tokens: TokenStore
    private lateinit var api: ApiClient
    private lateinit var auth: AuthService

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        tokens = TokenStore(this)
        api = ApiClient(tokens)
        auth = AuthService(this, api, tokens)

        setContent {
            MaterialTheme {
                FlyFunApp(auth = auth, tokens = tokens, api = api)
            }
        }
        handleAuthRedirect(intent)
    }

    /**
     * The activity is singleTask, so the OAuth redirect arrives here rather
     * than starting a second copy on top of the running task.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAuthRedirect(intent)
    }

    private fun handleAuthRedirect(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme != ApiConfig.CALLBACK_SCHEME) return
        lifecycleScope.launch {
            auth.handleCallback(uri)
                .onSuccess { recreate() }
                .onFailure {
                    Toast.makeText(
                        this@MainActivity,
                        it.message ?: "Sign-in failed",
                        Toast.LENGTH_LONG,
                    ).show()
                }
        }
    }
}
