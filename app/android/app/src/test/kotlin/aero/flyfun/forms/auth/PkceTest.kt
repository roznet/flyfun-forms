package aero.flyfun.forms.auth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PkceTest {

    @Test
    fun `challenge matches the RFC 7636 appendix B vector`() {
        assertEquals(
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
            Pkce.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
        )
    }

    @Test
    fun `verifier is valid for the server and random`() {
        val verifier = Pkce.newVerifier()
        // flyfun-common verify_pkce_s256: ^[A-Za-z0-9\-._~]{43,128}$
        assertTrue(Regex("^[A-Za-z0-9\\-._~]{43,128}$").matches(verifier))
        assertNotEquals(verifier, Pkce.newVerifier())
    }

    @Test
    fun `challenge is what the server accepts`() {
        // flyfun-common /auth/login: ^[A-Za-z0-9_-]{43}$
        assertTrue(Regex("^[A-Za-z0-9_-]{43}$").matches(Pkce.challenge(Pkce.newVerifier())))
    }
}
