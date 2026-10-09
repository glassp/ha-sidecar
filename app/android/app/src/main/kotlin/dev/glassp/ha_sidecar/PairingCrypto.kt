package dev.glassp.ha_sidecar

import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.spec.ECGenParameterSpec
import java.security.spec.X509EncodedKeySpec
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Cryptography of the pairing handshake (docs/PAIRING.md). Both sides generate an ephemeral P-256 key pair and
 * derive the same keys with ECDH + HKDF-SHA256; the tablet's short code is bound into a proof, credentials travel
 * AES-256-GCM encrypted. Kept free of Android classes so it is unit-tested on the JVM and cross-checked with the
 * Python side.
 */
object PairingCrypto {
    const val INFO = "ha-sidecar-pair-v1"
    private val random = SecureRandom()

    class Keys(val enc: ByteArray, val mac: ByteArray, val sasValue: Int) {
        /** Six digits both sides show so the user can compare them (confirm mode). */
        val sas: String get() = "%06d".format(sasValue)
    }

    fun newKeyPair(): KeyPair =
        KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()

    fun randomBytes(n: Int) = ByteArray(n).also { random.nextBytes(it) }

    /** X.509 SubjectPublicKeyInfo (DER), what Python's `public_bytes(DER, SubjectPublicKeyInfo)` produces. */
    fun publicBytes(pair: KeyPair): ByteArray = pair.public.encoded

    fun sharedSecret(own: KeyPair, peerPublicDer: ByteArray): ByteArray {
        val peer = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(peerPublicDer))
        return KeyAgreement.getInstance("ECDH").apply { init(own.private); doPhase(peer, true) }.generateSecret()
    }

    fun deriveKeys(shared: ByteArray, haNonce: ByteArray, tabletNonce: ByteArray): Keys {
        val okm = hkdf(shared, haNonce + tabletNonce, INFO.toByteArray(), 68)
        val sas = ((okm[64].toLong() and 0xff shl 24) or (okm[65].toLong() and 0xff shl 16) or
            (okm[66].toLong() and 0xff shl 8) or (okm[67].toLong() and 0xff))
        return Keys(okm.copyOfRange(0, 32), okm.copyOfRange(32, 64), (sas % 1_000_000L).toInt())
    }

    /** RFC 5869 HKDF with HMAC-SHA256. */
    fun hkdf(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
        val prk = hmac(if (salt.isEmpty()) ByteArray(32) else salt, ikm)
        var block = ByteArray(0)
        val out = ArrayList<Byte>()
        var counter = 1
        while (out.size < length) {
            block = hmac(prk, block + info + byteArrayOf(counter.toByte()))
            out.addAll(block.toList())
            counter++
        }
        return out.take(length).toByteArray()
    }

    fun hmac(key: ByteArray, data: ByteArray): ByteArray =
        Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(key, "HmacSHA256")) }.doFinal(data)

    /** Proof that the sender knows the code shown on the tablet; bound to this handshake through the MAC key. */
    fun proof(macKey: ByteArray, code: String): ByteArray = hmac(macKey, "ha-proof\u0000$code".toByteArray())

    fun constantTimeEquals(a: ByteArray, b: ByteArray) = MessageDigest.isEqual(a, b)

    class Sealed(val iv: ByteArray, val ciphertext: ByteArray)

    fun seal(encKey: ByteArray, plaintext: ByteArray, aad: ByteArray, iv: ByteArray = randomBytes(12)): Sealed {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, SecretKeySpec(encKey, "AES"), GCMParameterSpec(128, iv))
        c.updateAAD(aad)
        return Sealed(iv, c.doFinal(plaintext))
    }

    /** @throws javax.crypto.AEADBadTagException if the data was tampered with or the keys differ. */
    fun open(encKey: ByteArray, iv: ByteArray, ciphertext: ByteArray, aad: ByteArray): ByteArray {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, SecretKeySpec(encKey, "AES"), GCMParameterSpec(128, iv))
        c.updateAAD(aad)
        return c.doFinal(ciphertext)
    }

    /** Codes are typed by people: ignore case, dashes and spaces. */
    fun normalizeCode(code: String) = code.uppercase().filter { it.isLetterOrDigit() }

    /** 8 characters without look-alikes (no 0/O, 1/I/L), shown as XXXX-XXXX. */
    fun newCode(): String {
        val alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
        return (1..8).map { alphabet[random.nextInt(alphabet.length)] }.joinToString("")
    }

    fun displayCode(code: String) = code.chunked(4).joinToString("-")
}
