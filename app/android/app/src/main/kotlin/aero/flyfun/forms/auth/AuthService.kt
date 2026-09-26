package aero.flyfun.forms.auth

import aero.flyfun.forms.net.ApiClient
import aero.flyfun.forms.net.ApiConfig
import aero.flyfun.forms.net.ExchangeRequest
import android.content.Context
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.security.SecureRandom
import android.util.Base64

/** The sign-in providers the flyfun server offers, by their path segment in `/auth/login/{provider}`. */
enum class SignInProvider(val path: String) {
    GOOGLE("google"),

    /**
     * Sign in with Apple through the same web flow as Google: Apple posts back
     * to the server (`response_mode=form_post`), which then redirects to the
     * app with the auth code, so nothing Apple-specific happens on Android.
     * The native `POST /auth/apple/token` route needs the iOS SDK.
     */
    APPLE("apple"),
}

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

    /**
     * Why the sign-in screen is showing, when that is not obvious - shown there
     * until the next sign-in. Held here rather than in the screen that caused
     * it, which has already left composition by the time it would show it.
     */
    private val _signInNotice = MutableStateFlow<String?>(null)
    val signInNotice: StateFlow<String?> = _signInNotice.asStateFlow()

    /**
     * The `state` nonce, held between launching the tab and handling the
     * redirect.
     *
     * On disk rather than in a field: while the Custom Tab is in front, this
     * process is in the background and may be killed, and the redirect then
     * starts a fresh one that would refuse the callback. It is a one-use
     * anti-forgery nonce, not a credential, so plain app-private preferences
     * are enough; it expires after [PENDING_TTL_MILLIS] so an abandoned
     * sign-in cannot be completed much later.
     */
    private val pending = context.getSharedPreferences("flyfun-auth-pending", Context.MODE_PRIVATE)

    private var pendingState: String?
        get() {
            val state = pending.getString(KEY_STATE, null) ?: return null
            val age = System.currentTimeMillis() - pending.getLong(KEY_STARTED, 0)
            return state.takeIf { age in 0..PENDING_TTL_MILLIS }
        }
        set(value) {
            pending.edit().apply {
                if (value == null) {
                    remove(KEY_STATE); remove(KEY_STARTED)
                } else {
                    putString(KEY_STATE, value); putLong(KEY_STARTED, System.currentTimeMillis())
                }
            }.commit()
        }

    fun startSignIn(provider: SignInProvider) {
        val state = newState().also { pendingState = it }
        val url = Uri.parse(ApiConfig.BASE_URL).buildUpon()
            .appendPath("auth")
            .appendPath("login")
            .appendPath(provider.path)
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
            _signInNotice.value = null
            response.userId
        }
    }

    suspend fun signOut() {
        runCatching { api.auth.logout() }
        tokens.clear()
    }

    /**
     * Delete the account on the server, then sign out here.
     *
     * People, aircraft and flights stay on the device: they were never on the
     * server, and the pilot may want to keep using the app offline.
     */
    suspend fun deleteAccount(): Result<Unit> = runCatching {
        val response = api.auth.deleteAccount()
        if (response.code() == 401) {
            // ApiClient has already dropped the token, so the sign-in screen
            // replaces Settings before its error could show. Say it there.
            _signInNotice.value = "Your session had expired, so your account was not deleted. Sign in again to delete it."
        }
        if (!response.isSuccessful) error("The server returned ${response.code()}. Your account was not deleted.")
        tokens.clear()
    }

    val isSignedIn: Boolean get() = tokens.isSignedIn

    private companion object {
        const val KEY_STATE = "state"
        const val KEY_STARTED = "started_at"
        const val PENDING_TTL_MILLIS = 10 * 60 * 1000L
    }

    private fun newState(): String {
        val bytes = ByteArray(24)
        SecureRandom().nextBytes(bytes)
        // Server requires ^[A-Za-z0-9_-]{8,128}$ - URL-safe base64, unpadded.
        return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    }
}
