package com.atlassian.meridian

import com.fasterxml.jackson.annotation.JsonProperty
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import java.net.URI
import java.net.URL
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Base64
import java.util.Collections
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

// MARK: - Handoff Errors

sealed class HandoffError(message: String) : Exception(message) {
    class DisallowedURL(url: String) : HandoffError("URL not in allowlist: $url")
    class InvalidReturnState(detail: String) : HandoffError("Invalid return state: $detail")
    class ExpiredReturnState : HandoffError("Return state has expired")
    class ReplayedReturnState : HandoffError("Return state has already been used")
    class MissingReturnState : HandoffError("Return state parameter missing")
}

// MARK: - Return State Payload

/**
 * The decoded, verified content of a return-state token.
 */
data class ReturnStatePayload(
    /** The payment identifier embedded at token-creation time. */
    val paymentId: String,
    /** Unix timestamp (seconds) at which the token was issued. */
    val issuedAt: Long,
    /** Unique nonce used for replay prevention. */
    val nonce: String,
)

// MARK: - Return State Token

/**
 * Generates and verifies opaque, HMAC-SHA256-signed return-state tokens.
 *
 * Token format: `<base64url(json_payload)>.<hex_hmac>`
 */
object ReturnStateToken {
    private val mapper = ObjectMapper().registerKotlinModule()

    // MARK: Generation

    /** Build a signed token string for [paymentId]. */
    fun generate(paymentId: String, signingKey: ByteArray): String {
        val payload = ReturnStatePayload(
            paymentId = paymentId,
            issuedAt = System.currentTimeMillis() / 1000L,
            nonce = UUID.randomUUID().toString(),
        )
        return sign(payload, signingKey)
    }

    /** Build a signed token string from an existing payload (useful in tests). */
    fun sign(payload: ReturnStatePayload, signingKey: ByteArray): String {
        val json = mapper.writeValueAsString(payload)
        val base64Payload = base64URLEncode(json.toByteArray(StandardCharsets.UTF_8))
        val mac = hmacSha256(signingKey, base64Payload.toByteArray(StandardCharsets.UTF_8))
        val hexMac = mac.joinToString("") { "%02x".format(it) }
        return "$base64Payload.$hexMac"
    }

    // MARK: Verification

    /**
     * Verify the token signature and decode its payload.
     *
     * @throws HandoffError.InvalidReturnState on any structural or cryptographic problem.
     */
    fun verify(token: String, signingKey: ByteArray): ReturnStatePayload {
        val dotIndex = token.indexOf('.')
        if (dotIndex < 1 || dotIndex == token.length - 1) {
            throw HandoffError.InvalidReturnState("Malformed token: missing separator")
        }

        val base64Payload = token.substring(0, dotIndex)
        val providedHex = token.substring(dotIndex + 1)

        // Constant-time HMAC verification.
        val expectedMac = hmacSha256(signingKey, base64Payload.toByteArray(StandardCharsets.UTF_8))
        val providedMac = hexToBytes(providedHex)
            ?: throw HandoffError.InvalidReturnState("Invalid hex encoding in signature")

        if (!MessageDigest.isEqual(expectedMac, providedMac)) {
            throw HandoffError.InvalidReturnState("Signature mismatch")
        }

        // Decode the payload.
        val jsonBytes = base64URLDecode(base64Payload)
            ?: throw HandoffError.InvalidReturnState("Invalid base64url encoding")

        return try {
            mapper.readValue(jsonBytes, ReturnStatePayload::class.java)
        } catch (e: Exception) {
            throw HandoffError.InvalidReturnState("Payload decoding failed: ${e.message}")
        }
    }

    // MARK: Crypto helpers

    internal fun hmacSha256(key: ByteArray, data: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(data)
    }

    internal fun deriveKey(sessionId: String): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(sessionId.toByteArray(StandardCharsets.UTF_8))

    private fun base64URLEncode(data: ByteArray): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(data)

    private fun base64URLDecode(s: String): ByteArray? =
        try { Base64.getUrlDecoder().decode(s) } catch (_: Exception) { null }

    private fun hexToBytes(hex: String): ByteArray? {
        if (hex.length % 2 != 0) return null
        return try {
            ByteArray(hex.length / 2) { i ->
                hex.substring(i * 2, i * 2 + 2).toUByte(16).toByte()
            }
        } catch (_: Exception) { null }
    }
}

// MARK: - Return State Validator

/**
 * Thread-safe validator that checks token signature, expiry, and replay.
 *
 * @param signingKey  Raw HMAC signing key bytes.
 * @param tokenTTL    Maximum token lifetime in seconds (default 300 s / 5 min).
 */
class ReturnStateValidator(
    private val signingKey: ByteArray,
    private val tokenTTL: Long = 300L,
) {
    private val seenNonces: MutableSet<String> = Collections.newSetFromMap(ConcurrentHashMap())

    /**
     * Verify [token] and return its payload.
     *
     * @throws HandoffError.InvalidReturnState  bad signature or structure
     * @throws HandoffError.ExpiredReturnState  token older than [tokenTTL]
     * @throws HandoffError.ReplayedReturnState nonce already consumed
     */
    fun validate(token: String): ReturnStatePayload {
        val payload = ReturnStateToken.verify(token, signingKey)

        val nowSeconds = System.currentTimeMillis() / 1000L
        if (nowSeconds - payload.issuedAt > tokenTTL) {
            throw HandoffError.ExpiredReturnState()
        }

        if (!seenNonces.add(payload.nonce)) {
            throw HandoffError.ReplayedReturnState()
        }

        return payload
    }
}

// MARK: - Bank Handoff Manager

/**
 * Manages external bank handoff URLs and return-URL validation.
 *
 * Responsibilities:
 * - Enforce an allowlist of bank HTTPS hosts.
 * - Attach a signed opaque `returnState` query parameter to outbound bank URLs.
 * - Parse and validate `returnState` from inbound universal/app-link return URLs.
 */
class BankHandoffManager(
    sessionId: String,
    private val allowlist: Set<String> = DEFAULT_ALLOWLIST,
    tokenTTL: Long = 300L,
) {
    companion object {
        val DEFAULT_ALLOWLIST: Set<String> = setOf(
            "secure.worldpay.com",
            "payments.worldpay.com",
            "checkout.adyen.com",
            "live.adyen.com",
        )
    }

    private val signingKey: ByteArray = ReturnStateToken.deriveKey(sessionId)
    private val validator: ReturnStateValidator = ReturnStateValidator(signingKey, tokenTTL)

    // MARK: Outbound

    /**
     * Build a bank handoff URL with a signed `returnState` query parameter.
     *
     * @param bankURL      The target bank URL (must use HTTPS and be allowlisted).
     * @param paymentId    The payment identifier to embed in the return state.
     * @param returnScheme Custom URL scheme the bank should redirect back to.
     * @throws HandoffError.DisallowedURL if the URL fails allowlist checks.
     */
    fun buildHandoffURL(bankURL: String, paymentId: String, returnScheme: String): String {
        val uri = try { URI(bankURL) } catch (e: Exception) {
            throw HandoffError.DisallowedURL("Malformed URL: $bankURL")
        }

        if (uri.scheme != "https") {
            throw HandoffError.DisallowedURL("Only HTTPS bank URLs are permitted")
        }

        val host = uri.host ?: throw HandoffError.DisallowedURL("URL has no host: $bankURL")
        if (!allowlist.contains(host)) {
            throw HandoffError.DisallowedURL(bankURL)
        }

        val token = ReturnStateToken.generate(paymentId, signingKey)
        val separator = if (bankURL.contains('?')) '&' else '?'
        return "$bankURL${separator}returnState=$token&returnScheme=$returnScheme"
    }

    // MARK: Inbound

    /**
     * Handle a return URL from the bank (received via universal or app link).
     *
     * Extracts the `returnState` parameter and validates its signature, expiry, and nonce.
     *
     * @throws HandoffError.MissingReturnState  parameter absent or empty
     * @throws HandoffError.InvalidReturnState  bad signature or structure
     * @throws HandoffError.ExpiredReturnState  token has expired
     * @throws HandoffError.ReplayedReturnState nonce already used (replay attack)
     */
    fun handleReturnURL(returnURL: String): ReturnStatePayload {
        val uri = try { URI(returnURL) } catch (e: Exception) {
            throw HandoffError.MissingReturnState()
        }

        val query = uri.query ?: throw HandoffError.MissingReturnState()
        val params = query.split("&").associate { param ->
            val eq = param.indexOf('=')
            if (eq < 0) param to "" else param.substring(0, eq) to param.substring(eq + 1)
        }

        val token = params["returnState"]?.takeIf { it.isNotEmpty() }
            ?: throw HandoffError.MissingReturnState()

        return validator.validate(token)
    }
}
