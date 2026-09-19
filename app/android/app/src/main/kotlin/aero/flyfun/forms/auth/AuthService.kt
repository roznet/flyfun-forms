package aero.flyfun.forms.auth

import aero.flyfun.forms.net.ApiClient
import aero.flyfun.forms.net.ApiConfig
import aero.flyfun.forms.net.ExchangeRequest
import android.content.Context
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import java.security.SecureRandom
import android.util.Base64

/**
 * Google / Apple sign-in through a Chrome Custom Tab.
 *
 * Never an embedded WebView: a Custom Tab shares the browser's cookie jar, shows
 * the real origin in the URL bar, and keeps credentials out of the app's
 * process.
 *
 * The flow is the hardened auth-code one (flyfun-common
 * designs/oauth-deeplink-hardening.md), which matters more on Android than on
 * iOS: any app can register the `flyfunforms` scheme, so a token arriving in the
 * redirect URL would be interceptable. We send a `state` nonce, get back a
 * short-TTL `code`, and exchange it over HTTPS. The server only takes the
 * code-flow branch when `state` is present.
 */
class AuthService(
    private val context: Context,
    private val api: ApiClient,
    private val tokens: TokenStore,
) {

    /** Held between launching the tab and handling the redirect. */
    private var pendingState: String? = null

    fun startSignIn(provider: String = "google") {
        val state = newState().also { pendingState = it }
        val url = Uri.parse(ApiConfig.BASE_URL).buildUpon()
            .appendPath("auth")
            .appendPath("login")
            .appendPath(provider)
            // The server's native branch keys off `platform=ios`. That name is
            // historical - it means "native app", not the OS - and it is what
            // selects the custom-scheme redirect instead of a web session
            // cookie. Renaming it server-side would be a shared-code change
            // across both apps.
            .appendQueryParameter("platform", "ios")
            .appendQueryParameter("scheme", ApiConfig.CALLBACK_SCHEME)
            .appendQueryParameter("state", state)
            .build()

        CustomTabsIntent.Builder()
            .setShowTitle(true)
            .build()
            .launchUrl(context, url)
    }

    /**
     * Handle `flyfunforms://auth/callback?code=...&state=...`.
     *
     * @return the signed-in user id, or null when this was not a callback we
     *   started.
     */
    suspend fun handleCallback(uri: Uri): Result<String> {
        val code = uri.getQueryParameter("code")
        val state = uri.getQueryParameter("state")

        if (code == null) {
            // The server falls back to a token in the URL for clients that send
            // no `state`. We always send one, so seeing this means something
            // else produced the redirect - refuse it rather than trusting a
            // token that arrived over a scheme any app can claim.
            return Result.failure(IllegalStateException("Sign-in did not return an auth code"))
        }
        val expected = pendingState
        if (expected == null || state != expected) {
            return Result.failure(IllegalStateException("Sign-in state did not match"))
        }
        pendingState = null

        return runCatching {
            val response = api.auth.exchange(ExchangeRequest(code = code, state = state))
            tokens.token = response.token
            response.userId
        }
    }

    suspend fun signOut() {
        runCatching { api.auth.logout() }
        tokens.clear()
    }

    val isSignedIn: Boolean get() = tokens.isSignedIn

    private fun newState(): String {
        val bytes = ByteArray(24)
        SecureRandom().nextBytes(bytes)
        // Server requires ^[A-Za-z0-9_-]{8,128}$ - URL-safe base64, unpadded.
        return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    }
}
