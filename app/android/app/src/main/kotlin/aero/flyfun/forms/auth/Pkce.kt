package aero.flyfun.forms.auth

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

/**
 * PKCE (RFC 7636, S256) for the native sign-in.
 *
 * The redirect back into the app uses the `flyfunforms` custom scheme, which
 * any installed app can also register, so another app could receive the
 * `code` and `state`. The server binds the code to [challenge] of a verifier
 * that never leaves this app, and `/auth/exchange` refuses the code without
 * that verifier.
 *
 * Plain JVM (java.util.Base64, not android.util.Base64) so it is unit-testable.
 */
object Pkce {
    private val encoder = Base64.getUrlEncoder().withoutPadding()

    /** 64 random bytes as unpadded base64url: 86 chars, within RFC 7636's 43-128. */
    fun newVerifier(): String {
        val bytes = ByteArray(64)
        SecureRandom().nextBytes(bytes)
        return encoder.encodeToString(bytes)
    }

    /** `BASE64URL(SHA-256(verifier))`, sent as `code_challenge` with method `S256`. */
    fun challenge(verifier: String): String =
        encoder.encodeToString(MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.US_ASCII)))
}
