package aero.flyfun.forms.auth

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * The session JWT, in EncryptedSharedPreferences backed by a Keystore master
 * key - the nearest equivalent to the iOS app's Keychain storage.
 *
 * App-private storage is already encrypted at rest on modern Android, but only
 * up to first unlock after boot. A bearer token for an account holding passport
 * data is worth the extra key.
 */
class TokenStore(context: Context) {

    private val prefs: SharedPreferences = run {
        val key = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "flyfun-auth",
            key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    var token: String?
        get() = prefs.getString(KEY_TOKEN, null)
        set(value) = prefs.edit().apply {
            if (value == null) remove(KEY_TOKEN) else putString(KEY_TOKEN, value)
        }.apply()

    val isSignedIn: Boolean get() = token != null

    fun clear() {
        token = null
    }

    private companion object {
        const val KEY_TOKEN = "session_jwt"
    }
}
