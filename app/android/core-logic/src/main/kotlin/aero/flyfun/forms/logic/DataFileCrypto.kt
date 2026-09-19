package aero.flyfun.forms.logic

import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/**
 * Password-based encryption for the "move my data" file.
 *
 * The file leaves the app sandbox - into Downloads, a share sheet, a chat app -
 * and it contains passport numbers. Plaintext passport data sitting in a
 * Downloads folder is exactly the artifact to avoid, so encryption is the
 * default and the plaintext GDPR export is a separate, explicitly labelled
 * action.
 *
 * AES-256-GCM with a PBKDF2-HMAC-SHA256 derived key. PBKDF2 rather than
 * Argon2id only because it is in the JDK: no extra dependency, and the same
 * primitives are available to CryptoKit on iOS, which matters for a format
 * meant to cross platforms.
 *
 * Layout: MAGIC | version | salt(16) | nonce(12) | ciphertext+tag
 */
object DataFileCrypto {

    private val MAGIC = "FFFORMS".toByteArray(Charsets.US_ASCII)
    private const val VERSION: Byte = 1
    private const val SALT_BYTES = 16
    private const val NONCE_BYTES = 12
    private const val KEY_BITS = 256
    private const val TAG_BITS = 128

    /** OWASP's 2023 floor for PBKDF2-HMAC-SHA256. */
    private const val ITERATIONS = 210_000

    class WrongPasswordException : Exception("That password does not match this file.")
    class NotOurFileException : Exception("This is not a FlyFun Forms data file.")

    fun encrypt(plaintext: String, password: CharArray): ByteArray {
        val random = SecureRandom()
        val salt = ByteArray(SALT_BYTES).also(random::nextBytes)
        val nonce = ByteArray(NONCE_BYTES).also(random::nextBytes)
        val key = deriveKey(password, salt)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(TAG_BITS, nonce))
        val body = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))

        return MAGIC + byteArrayOf(VERSION) + salt + nonce + body
    }

    /**
     * @throws NotOurFileException when the header is not ours
     * @throws WrongPasswordException when GCM authentication fails, which is
     *   the same signal as a tampered file. Either way the import stops before
     *   writing anything rather than half-applying.
     */
    fun decrypt(data: ByteArray, password: CharArray): String {
        val headerSize = MAGIC.size + 1 + SALT_BYTES + NONCE_BYTES
        if (data.size <= headerSize) throw NotOurFileException()
        if (!data.copyOfRange(0, MAGIC.size).contentEquals(MAGIC)) throw NotOurFileException()
        if (data[MAGIC.size] != VERSION) throw NotOurFileException()

        var offset = MAGIC.size + 1
        val salt = data.copyOfRange(offset, offset + SALT_BYTES); offset += SALT_BYTES
        val nonce = data.copyOfRange(offset, offset + NONCE_BYTES); offset += NONCE_BYTES
        val body = data.copyOfRange(offset, data.size)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, deriveKey(password, salt), GCMParameterSpec(TAG_BITS, nonce))
        return try {
            String(cipher.doFinal(body), Charsets.UTF_8)
        } catch (_: javax.crypto.AEADBadTagException) {
            throw WrongPasswordException()
        } catch (_: javax.crypto.BadPaddingException) {
            throw WrongPasswordException()
        }
    }

    fun looksEncrypted(data: ByteArray): Boolean =
        data.size > MAGIC.size && data.copyOfRange(0, MAGIC.size).contentEquals(MAGIC)

    private fun deriveKey(password: CharArray, salt: ByteArray): SecretKeySpec {
        val spec = PBEKeySpec(password, salt, ITERATIONS, KEY_BITS)
        val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        return SecretKeySpec(factory.generateSecret(spec).encoded, "AES")
    }

    /**
     * A transfer passphrase the user reads off one device and types into the
     * other.
     *
     * Six words from a small, unambiguous list beats a user-chosen password,
     * which would be weak and reused - and reads naturally as a one-time code
     * rather than as an account credential.
     */
    fun generatePassphrase(words: Int = 6): String {
        val random = SecureRandom()
        return (1..words).joinToString("-") { WORDS[random.nextInt(WORDS.size)] }
    }

    /** Deliberately short, aviation-flavoured, and free of easily confused pairs. */
    private val WORDS = listOf(
        "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel",
        "india", "juliet", "kilo", "lima", "mike", "november", "oscar", "papa",
        "quebec", "romeo", "sierra", "tango", "uniform", "victor", "whiskey",
        "xray", "yankee", "zulu", "runway", "taxiway", "apron", "hangar",
        "compass", "rudder", "aileron", "throttle", "cockpit", "propeller",
    )
}
