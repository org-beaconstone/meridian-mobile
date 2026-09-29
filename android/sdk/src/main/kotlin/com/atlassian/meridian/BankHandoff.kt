package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import java.net.URL
import java.util.Base64
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

// MARK: - Bank Handoff Errors

/**
 * Errors produced during bank URL construction or return state validation.
 * None of these errors trigger payment recreation — callers must surface a
 * safe failure message and retain the original idempotency key for retry.
 */
sealed class BankHandoffError(message: String) : Exception(message) {
  /** The target URL's host is not on the allowlist or is not HTTPS */
  class DomainNotAllowed(host: String) : BankHandoffError("Bank domain not in allowlist: $host")

  /** The state token could not be parsed */
  class MalformedToken(detail: String = "Return state token is malformed") :
    BankHandoffError(detail)

  /** The HMAC signature on the state token does not match */
  class InvalidSignature : BankHandoffError("Return state token signature is invalid")

  /** The state token's issuedAt timestamp is outside the allowed window */
  class TokenExpired : BankHandoffError("Return state token has expired")

  /** The state token's nonce has already been consumed (replay attack) */
  class TokenReplayed : BankHandoffError("Return state token has already been consumed")
}

// MARK: - Bank Handoff

/**
 * Utilities for external bank handoff: constructing allowlist-validated HTTPS URLs
 * with signed opaque state tokens, and validating tokens on app-link return.
 *
 * Token format: `<base64url(JSON)>.<base64url(HMAC-SHA256)>`
 *
 * The JSON payload contains `paymentId`, `nonce`, and `iat` (Unix epoch seconds).
 * The HMAC is computed over the base64url-encoded payload using the provided key bytes.
 */
object BankHandoff {

  private val mapper = ObjectMapper().registerKotlinModule()

  // MARK: - Allowlist

  /**
   * HTTPS hostnames the app is permitted to open for bank payment handoff.
   * Only Worldpay is the baseline bank provider; the rehearsal endpoint covers testing.
   */
  val allowedHosts: Set<String> = setOf(
    "payments.worldpay.com",
    "secure.worldpay.com",
    "online.worldpay.com",
    "banking.worldpay.com",
    "bank.rehearsal.meridian.internal",
  )

  // MARK: - URL Building

  /**
   * Construct an external bank handoff URL with a signed opaque `state` parameter
   * and a `redirect_uri` pointing back into the app.
   *
   * @param bankURL The bank's HTTPS base URL string (host must be in [allowedHosts])
   * @param paymentId Payment identifier to embed in the state token
   * @param returnURLScheme The app's registered deep-link scheme (e.g. "meridian")
   * @param signingKey Raw bytes of the HMAC-SHA256 signing key
   * @throws BankHandoffError.DomainNotAllowed if the host or scheme is not permitted
   * @return The bank URL string with `state` and `redirect_uri` appended
   */
  fun buildHandoffURL(
    bankURL: String,
    paymentId: String,
    returnURLScheme: String,
    signingKey: ByteArray,
  ): String {
    val parsed = runCatching { URL(bankURL) }.getOrElse {
      throw BankHandoffError.MalformedToken("Invalid bank URL: $bankURL")
    }
    if (parsed.protocol?.lowercase() != "https" || parsed.host !in allowedHosts) {
      throw BankHandoffError.DomainNotAllowed(
        "${parsed.protocol ?: ""}://${parsed.host ?: "(none)"}"
      )
    }

    val stateToken = makeStateToken(paymentId, signingKey)
    val returnURL = "$returnURLScheme://payment/return"

    val separator = if (bankURL.contains("?")) "&" else "?"
    val encodedState = java.net.URLEncoder.encode(stateToken, "UTF-8")
    val encodedReturn = java.net.URLEncoder.encode(returnURL, "UTF-8")
    return "$bankURL${separator}state=$encodedState&redirect_uri=$encodedReturn"
  }

  // MARK: - Return URL Validation

  /**
   * Extract and validate the `state` token from a bank return URL string.
   *
   * Validates in order: HMAC signature → expiry → replay (nonce uniqueness).
   * A nonce is added to [usedNonces] only after all checks pass.
   * Replayed, expired, or tampered tokens throw without touching payment state.
   *
   * @param urlString The return deep-link URL delivered via app link or custom scheme
   * @param signingKey The same key bytes used when building the handoff URL
   * @param usedNonces Mutable set of already-consumed nonces; updated on success
   * @param maxAgeMs Token lifetime in milliseconds (default 600 000 = 10 minutes)
   * @return The decoded [ReturnState] on success
   * @throws BankHandoffError describing the failure
   */
  fun validateReturnURL(
    urlString: String,
    signingKey: ByteArray,
    usedNonces: MutableSet<String>,
    maxAgeMs: Long = 600_000L,
  ): ReturnState {
    val stateToken = extractStateParam(urlString)
      ?: throw BankHandoffError.MalformedToken("Missing state parameter in return URL")
    return verifyStateToken(stateToken, signingKey, usedNonces, maxAgeMs)
  }

  // MARK: - Internal Token Helpers

  internal fun makeStateToken(paymentId: String, signingKey: ByteArray): String {
    val nowSeconds = System.currentTimeMillis() / 1000L
    val payload = mapOf(
      "paymentId" to paymentId,
      "nonce" to UUID.randomUUID().toString(),
      "iat" to nowSeconds,
    )
    val payloadJson = mapper.writeValueAsString(payload)
    val payloadB64 = base64urlEncode(payloadJson.toByteArray(Charsets.UTF_8))
    val sig = hmacSha256(signingKey, payloadB64.toByteArray(Charsets.UTF_8))
    val sigB64 = base64urlEncode(sig)
    return "$payloadB64.$sigB64"
  }

  internal fun verifyStateToken(
    token: String,
    signingKey: ByteArray,
    usedNonces: MutableSet<String>,
    maxAgeMs: Long,
  ): ReturnState {
    val dot = token.indexOf('.')
    if (dot < 1 || dot == token.lastIndex) throw BankHandoffError.MalformedToken()

    val payloadB64 = token.substring(0, dot)
    val sigB64 = token.substring(dot + 1)

    // Verify HMAC
    val expectedSig = hmacSha256(signingKey, payloadB64.toByteArray(Charsets.UTF_8))
    val providedSig = base64urlDecode(sigB64) ?: throw BankHandoffError.MalformedToken()
    if (!constantTimeEquals(expectedSig, providedSig)) throw BankHandoffError.InvalidSignature()

    // Decode payload
    val payloadBytes = base64urlDecode(payloadB64) ?: throw BankHandoffError.MalformedToken()
    val payloadMap = runCatching {
      @Suppress("UNCHECKED_CAST")
      mapper.readValue(payloadBytes, Map::class.java) as Map<String, Any>
    }.getOrElse { throw BankHandoffError.MalformedToken("Cannot parse token payload") }

    val paymentId = payloadMap["paymentId"] as? String ?: throw BankHandoffError.MalformedToken()
    val nonce = payloadMap["nonce"] as? String ?: throw BankHandoffError.MalformedToken()
    val iat = when (val raw = payloadMap["iat"]) {
      is Number -> raw.toLong()
      else -> throw BankHandoffError.MalformedToken()
    }

    // Expiry check (iat is in seconds; maxAgeMs is in milliseconds)
    val nowMs = System.currentTimeMillis()
    val ageMs = nowMs - iat * 1000L
    if (ageMs < 0 || ageMs > maxAgeMs) throw BankHandoffError.TokenExpired()

    // Replay check
    if (nonce in usedNonces) throw BankHandoffError.TokenReplayed()
    usedNonces.add(nonce)

    return ReturnState(paymentId = paymentId, nonce = nonce, issuedAt = iat)
  }

  // MARK: - Crypto Helpers

  private fun hmacSha256(key: ByteArray, data: ByteArray): ByteArray {
    val mac = Mac.getInstance("HmacSHA256")
    mac.init(SecretKeySpec(key, "HmacSHA256"))
    return mac.doFinal(data)
  }

  /** Constant-time byte array comparison to prevent timing attacks */
  private fun constantTimeEquals(a: ByteArray, b: ByteArray): Boolean {
    if (a.size != b.size) return false
    var diff = 0
    for (i in a.indices) diff = diff or (a[i].toInt() xor b[i].toInt())
    return diff == 0
  }

  // MARK: - Base64url Codec

  internal fun base64urlEncode(data: ByteArray): String =
    Base64.getUrlEncoder().withoutPadding().encodeToString(data)

  internal fun base64urlDecode(s: String): ByteArray? =
    runCatching { Base64.getUrlDecoder().decode(s) }.getOrNull()

  // MARK: - URL Parsing Helper

  private fun extractStateParam(urlString: String): String? {
    val queryStart = urlString.indexOf('?').takeIf { it >= 0 } ?: return null
    val query = urlString.substring(queryStart + 1)
    return query.split("&")
      .mapNotNull { pair ->
        val eq = pair.indexOf('=')
        if (eq < 0) null else {
          val key = java.net.URLDecoder.decode(pair.substring(0, eq), "UTF-8")
          val value = java.net.URLDecoder.decode(pair.substring(eq + 1), "UTF-8")
          key to value
        }
      }
      .firstOrNull { it.first == "state" }
      ?.second
  }
}
