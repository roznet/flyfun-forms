package aero.flyfun.forms.auth

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The session JWT, encrypted with an AES-GCM key that never leaves the Android
 * Keystore - the nearest equivalent to the iOS app's Keychain storage.
 *
 * App-private storage is already encrypted at rest on modern Android, but only
 * up to first unlock after boot. A bearer token for an account holding passport
 * data is worth the extra key.
 *
 * Replaces `EncryptedSharedPreferences`, which androidx.security deprecated:
 * one value does not need an encrypted key-value store, only its own key. The
 * ciphertext (IV first) sits in plain app-private preferences.
 */
class TokenStore(context: Context) {

    private val prefs: SharedPreferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    init {
        // The EncryptedSharedPreferences file an earlier build kept the token
        // in. Not carried over: the app was never released, and signing in
        // once more is the whole cost.
        context.deleteSharedPreferences(LEGACY_PREFS)
    }

    @Volatile
    private var cached: String? = read()

    private val _signedIn = MutableStateFlow(cached != null)

    /** Observed by the UI, so a sign-out or an expired token shows the sign-in screen. */
    val signedIn: StateFlow<Boolean> = _signedIn.asStateFlow()

    var token: String?
        get() = cached
        @Synchronized
        set(value) {
            cached = value
            val stored = value?.let { runCatching { encrypt(it) }.getOrNull() }
            prefs.edit().apply {
                if (stored == null) remove(KEY_TOKEN) else putString(KEY_TOKEN, stored)
            }.apply()
            _signedIn.value = value != null
        }

    val isSignedIn: Boolean get() = token != null

    fun clear() {
        token = null
    }

    /**
     * Drop [rejected] after the server answered 401 to it - unless a newer
     * token has replaced it meanwhile, which a late 401 must not throw away.
     */
    @Synchronized
    fun clearIfCurrent(rejected: String) {
        if (token == rejected) clear()
    }

    /**
     * Take the successor the server minted for [sent] as it neared expiry
     * (flyfun-common's rolling sessions, `X-Renewed-Token`). Only while [sent]
     * is still the one held: a sign-out or a newer renewal meanwhile wins.
     */
    @Synchronized
    fun replaceIfCurrent(sent: String, renewed: String) {
        if (token == sent && renewed.isNotBlank()) token = renewed
    }

    /** The stored token, or null when there is none or it no longer decrypts (key lost with a reset lock screen, say). */
    private fun read(): String? {
        val stored = prefs.getString(KEY_TOKEN, null) ?: return null
        return runCatching { decrypt(stored) }.getOrElse {
            prefs.edit().remove(KEY_TOKEN).apply()
            null
        }
    }

    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private fun encrypt(plain: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.iv + cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(sealed, Base64.NO_WRAP)
    }

    private fun decrypt(stored: String): String {
        val sealed = Base64.decode(stored, Base64.NO_WRAP)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, sealed, 0, IV_BYTES))
        return String(cipher.doFinal(sealed, IV_BYTES, sealed.size - IV_BYTES), Charsets.UTF_8)
    }

    private companion object {
        const val PREFS = "flyfun-session"
        const val LEGACY_PREFS = "flyfun-auth"
        const val KEY_TOKEN = "session_jwt"
        const val KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "flyfun-session-token"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
        const val TAG_BITS = 128
    }
}
