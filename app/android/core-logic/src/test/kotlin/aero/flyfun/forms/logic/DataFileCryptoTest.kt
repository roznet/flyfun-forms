package aero.flyfun.forms.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class DataFileCryptoTest {

    private val password = "alpha-bravo-charlie-delta-echo-foxtrot".toCharArray()
    private val payload = """{"format":"flyfun-forms/data","people":[{"id":"a"}]}"""

    @Test
    fun `round trips`() {
        val blob = DataFileCrypto.encrypt(payload, password)
        assertEquals(payload, DataFileCrypto.decrypt(blob, password.copyOf()))
    }

    @Test
    fun `the wrong password fails cleanly rather than returning junk`() {
        val blob = DataFileCrypto.encrypt(payload, password)
        assertThrows(DataFileCrypto.WrongPasswordException::class.java) {
            DataFileCrypto.decrypt(blob, "wrong-wrong-wrong".toCharArray())
        }
    }

    @Test
    fun `a tampered byte is detected, not silently decrypted`() {
        val blob = DataFileCrypto.encrypt(payload, password)
        blob[blob.size - 1] = (blob[blob.size - 1] + 1).toByte()
        assertThrows(DataFileCrypto.WrongPasswordException::class.java) {
            DataFileCrypto.decrypt(blob, password.copyOf())
        }
    }

    @Test
    fun `a foreign file is refused by its header`() {
        assertThrows(DataFileCrypto.NotOurFileException::class.java) {
            DataFileCrypto.decrypt("just some bytes that are long enough to pass".toByteArray(), password)
        }
    }

    @Test
    fun `plaintext is never visible in the ciphertext`() {
        val blob = DataFileCrypto.encrypt(payload, password)
        assertTrue(!String(blob, Charsets.ISO_8859_1).contains("flyfun-forms"))
    }

    @Test
    fun `the same plaintext encrypts differently every time`() {
        // Random salt and nonce per file, so two exports are not comparable.
        val a = DataFileCrypto.encrypt(payload, password)
        val b = DataFileCrypto.encrypt(payload, password.copyOf())
        assertNotEquals(String(a, Charsets.ISO_8859_1), String(b, Charsets.ISO_8859_1))
    }

    @Test
    fun `encrypted files are recognisable without the password`() {
        assertTrue(DataFileCrypto.looksEncrypted(DataFileCrypto.encrypt(payload, password)))
        assertTrue(!DataFileCrypto.looksEncrypted(payload.toByteArray()))
    }

    @Test
    fun `generated passphrases are usable and distinct`() {
        val one = DataFileCrypto.generatePassphrase()
        val two = DataFileCrypto.generatePassphrase()
        assertEquals(6, one.split("-").size)
        assertNotEquals(one, two)
        // and it actually works as a password
        val blob = DataFileCrypto.encrypt(payload, one.toCharArray())
        assertEquals(payload, DataFileCrypto.decrypt(blob, one.toCharArray()))
    }
}
