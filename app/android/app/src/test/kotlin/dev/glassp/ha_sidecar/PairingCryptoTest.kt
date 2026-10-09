package dev.glassp.ha_sidecar

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

class PairingCryptoTest {
    private fun b64(b: ByteArray) = Base64.getEncoder().encodeToString(b)

    @Test fun bothSidesDeriveTheSameKeys() {
        val a = PairingCrypto.newKeyPair()
        val b = PairingCrypto.newKeyPair()
        val n1 = PairingCrypto.randomBytes(16)
        val n2 = PairingCrypto.randomBytes(16)
        val ka = PairingCrypto.deriveKeys(PairingCrypto.sharedSecret(a, PairingCrypto.publicBytes(b)), n1, n2)
        val kb = PairingCrypto.deriveKeys(PairingCrypto.sharedSecret(b, PairingCrypto.publicBytes(a)), n1, n2)
        assertArrayEquals(ka.enc, kb.enc)
        assertArrayEquals(ka.mac, kb.mac)
        assertEquals(ka.sas, kb.sas)
        assertEquals(6, ka.sas.length)
    }

    /** Vectors produced with Python `cryptography` (HKDF, HMAC, AESGCM): both implementations must agree. */
    @Test fun matchesThePythonImplementation() {
        val shared = ByteArray(32) { it.toByte() }
        val n1 = ByteArray(16) { (0x10 + it).toByte() }
        val n2 = ByteArray(16) { (0x20 + it).toByte() }
        val keys = PairingCrypto.deriveKeys(shared, n1, n2)
        assertEquals("nz2Gqcd7f/zrlr0bSFuKSQFErsB4Mgqrr3If8wWEW1E=", b64(keys.enc))
        assertEquals("2PB8mc7QZxG1Pn+XGhmwK9GMWBRzIfwNHKuDPTM8ENw=", b64(keys.mac))
        assertEquals("631215", keys.sas)
        assertEquals("M5/5C2DTTEPRPqV/c45alw01L+C/yeo+YxFB6I+JThA=", b64(PairingCrypto.proof(keys.mac, "ABCD2345")))
        val iv = ByteArray(12) { (0x30 + it).toByte() }
        val sealed = PairingCrypto.seal(keys.enc, "{\"token\":\"t\"}".toByteArray(), "aad".toByteArray(), iv)
        assertEquals("6l1UDXzFo6RX6lWJXIxcHqT1tdeBJdJj4L4YxnQ=", b64(sealed.ciphertext))
    }

    @Test fun sealedDataRoundTripsAndDetectsTampering() {
        val key = PairingCrypto.randomBytes(32)
        val s = PairingCrypto.seal(key, "secret".toByteArray(), "aad".toByteArray())
        assertEquals("secret", String(PairingCrypto.open(key, s.iv, s.ciphertext, "aad".toByteArray())))
        val bad = s.ciphertext.copyOf().also { it[0] = (it[0] + 1).toByte() }
        assertTrue(runCatching { PairingCrypto.open(key, s.iv, bad, "aad".toByteArray()) }.isFailure)
        assertTrue(runCatching { PairingCrypto.open(key, s.iv, s.ciphertext, "other".toByteArray()) }.isFailure)
    }

    @Test fun codesAreUnambiguousAndNormalized() {
        repeat(50) {
            val c = PairingCrypto.newCode()
            assertEquals(8, c.length)
            assertFalse(c.any { it in "01OIL" })
        }
        assertEquals("ABCD2345", PairingCrypto.normalizeCode("abcd-2345 "))
        assertEquals("ABCD-2345", PairingCrypto.displayCode("ABCD2345"))
    }
}
