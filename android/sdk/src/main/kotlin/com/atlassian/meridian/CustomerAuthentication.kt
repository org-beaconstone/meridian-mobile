package com.atlassian.meridian

import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Rehearsal strong customer authentication and Worldpay bank return checks.
 * Card payments clear only after a biometric or PIN confirmation. Bank payments
 * open an allowlisted HTTPS handoff and clear only after the signed return
 * state passes integrity, expiry, and replay checks. Nothing here calls a
 * live card or bank host.
 */
enum class ScaFactor {
  biometric,
  pin,
}

enum class ReturnFailure {
  invalid,
  expired,
  replayed,
  missing,
}

sealed class ScaDecision {
  data class Confirmed(val factor: ScaFactor) : ScaDecision()
  data object Rejected : ScaDecision()
  data object NotRequired : ScaDecision()
}

sealed class ReturnStatus {
  data class Accepted(val nonce: String) : ReturnStatus()
  data class Rejected(val reason: ReturnFailure) : ReturnStatus()
}

sealed class ReturnIntercept {
  data class Token(val token: String) : ReturnIntercept()
  data object MissingState : ReturnIntercept()
  data object NotReturnLink : ReturnIntercept()
}

sealed class ReturnOutcome {
  data class Cleared(val idempotencyKey: String) : ReturnOutcome()
  data class SafeFailure(val reason: ReturnFailure, val idempotencyKey: String) : ReturnOutcome()
  data object Ignored : ReturnOutcome()
}

fun normalizeRehearsalPin(pin: String): String? {
  val trimmed = pin.trim()
  if (trimmed.length !in 4..8) return null
  if (trimmed.any { it !in '0'..'9' }) return null
  return trimmed
}

fun returnFailureMessage(reason: ReturnFailure): String = when (reason) {
  ReturnFailure.invalid -> "The bank return could not be verified. The payment was not sent again."
  ReturnFailure.expired -> "The bank return expired. The payment was not sent again."
  ReturnFailure.replayed -> "The bank return was already used. The payment was not sent again."
  ReturnFailure.missing -> "The bank return was missing its state. The payment was not sent again."
}

internal fun base64UrlEncode(data: ByteArray): String {
  if (data.isEmpty()) return ""
  val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  val out = StringBuilder(((data.size + 2) / 3) * 4)
  var index = 0
  while (index + 3 <= data.size) {
    val packed = ((data[index].toInt() and 0xFF) shl 16) or
      ((data[index + 1].toInt() and 0xFF) shl 8) or
      (data[index + 2].toInt() and 0xFF)
    out.append(alphabet[(packed shr 18) and 63])
    out.append(alphabet[(packed shr 12) and 63])
    out.append(alphabet[(packed shr 6) and 63])
    out.append(alphabet[packed and 63])
    index += 3
  }
  val remaining = data.size - index
  if (remaining == 1) {
    val packed = (data[index].toInt() and 0xFF) shl 16
    out.append(alphabet[(packed shr 18) and 63])
    out.append(alphabet[(packed shr 12) and 63])
  } else if (remaining == 2) {
    val packed = ((data[index].toInt() and 0xFF) shl 16) or ((data[index + 1].toInt() and 0xFF) shl 8)
    out.append(alphabet[(packed shr 18) and 63])
    out.append(alphabet[(packed shr 12) and 63])
    out.append(alphabet[(packed shr 6) and 63])
  }
  return out.toString()
}

internal fun base64UrlDecode(text: String): ByteArray? {
  if (text.isEmpty()) return ByteArray(0)
  if (text.length % 4 == 1) return null
  val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  val map = IntArray(128) { -1 }
  alphabet.forEachIndexed { index, char -> map[char.code] = index }
  val outLen = when (text.length % 4) {
    0 -> text.length / 4 * 3
    2 -> text.length / 4 * 3 + 1
    3 -> text.length / 4 * 3 + 2
    else -> return null
  }
  val out = ByteArray(outLen)
  var written = 0
  var buffer = 0
  var bits = 0
  for (char in text) {
    if (char.code >= 128) return null
    val value = map[char.code]
    if (value < 0) return null
    buffer = (buffer shl 6) or value
    bits += 6
    if (bits >= 8) {
      bits -= 8
      if (written >= out.size) return null
      out[written++] = ((buffer shr bits) and 0xFF).toByte()
    }
  }
  if (written != outLen) return null
  return out
}

object BankAllowlist {
  const val BANK_HOST = "bank.worldpay.rehearsal.meridian.example"
  const val RETURN_HOST = "app.meridian.example"
  const val RETURN_PATH = "/bank/return"
  const val RETURN_URL = "https://app.meridian.example/bank/return"
  const val HANDOFF_PATH = "/open-banking/authorize"

  fun handoffUrl(stateToken: String): String? {
    if (stateToken.isBlank() || stateToken.length > 512) return null
    val query = "redirect_uri=${urlEncode(RETURN_URL)}&state=${urlEncode(stateToken)}"
    val url = "https://$BANK_HOST$HANDOFF_PATH?$query"
    return if (permitsHandoff(url)) url else null
  }

  fun returnUrl(stateToken: String): String? {
    if (stateToken.isBlank()) return null
    val url = "https://$RETURN_HOST$RETURN_PATH?state=${urlEncode(stateToken)}"
    return if (intercept(url) is ReturnIntercept.Token) url else null
  }

  fun permitsHandoff(url: String): Boolean {
    val uri = parse(url) ?: return false
    if (uri.scheme != "https") return false
    if (uri.userInfo != null) return false
    if (uri.port != -1) return false
    if (uri.host != BANK_HOST) return false
    if (uri.path != HANDOFF_PATH) return false
    val items = queryItems(uri.rawQuery) ?: return false
    val state = items["state"]
    val redirect = items["redirect_uri"]
    return !state.isNullOrBlank() && redirect == RETURN_URL
  }

  fun intercept(url: String): ReturnIntercept {
    val uri = parse(url) ?: return ReturnIntercept.NotReturnLink
    if (uri.scheme != "https" || uri.userInfo != null || uri.host != RETURN_HOST) {
      return ReturnIntercept.NotReturnLink
    }
    val rawPath = uri.path ?: return ReturnIntercept.NotReturnLink
    val path = if (rawPath.length > 1 && rawPath.endsWith("/")) rawPath.dropLast(1) else rawPath
    if (path != RETURN_PATH) return ReturnIntercept.NotReturnLink
    val state = queryItems(uri.rawQuery)?.get("state")
    if (state.isNullOrBlank()) return ReturnIntercept.MissingState
    return ReturnIntercept.Token(state)
  }

  fun openIfAllowlisted(url: String, open: (String) -> Boolean): Boolean {
    if (!permitsHandoff(url)) return false
    return open(url)
  }

  private fun parse(url: String): URI? = try {
    URI(url)
  } catch (_: Exception) {
    null
  }

  private fun queryItems(rawQuery: String?): Map<String, String>? {
    if (rawQuery.isNullOrEmpty()) return emptyMap()
    val items = linkedMapOf<String, String>()
    for (part in rawQuery.split("&")) {
      if (part.isEmpty()) continue
      val pieces = part.split("=", limit = 2)
      val name = urlDecode(pieces[0]) ?: return null
      val value = if (pieces.size == 2) urlDecode(pieces[1]) ?: return null else ""
      items[name] = value
    }
    return items
  }

  private fun urlEncode(value: String): String =
    URLEncoder.encode(value, StandardCharsets.UTF_8.name())

  private fun urlDecode(value: String): String? = try {
    URLDecoder.decode(value, StandardCharsets.UTF_8.name())
  } catch (_: IllegalArgumentException) {
    null
  }
}

class ReturnStateSigner(
  secret: ByteArray,
  private val ttlSeconds: Long = 300,
  private val clock: () -> Long = { System.currentTimeMillis() / 1000 },
  private val random: (Int) -> ByteArray = { count ->
    ByteArray(count).also { SecureRandom().nextBytes(it) }
  },
) {
  private val secret = secret.copyOf()
  private val consumed = linkedSetOf<String>()

  init {
    require(secret.size >= 16) { "Return state signing secret is too short" }
    require(ttlSeconds in 30..900) { "Return state lifetime is out of range" }
  }

  fun issue(binding: String): String {
    require(binding.isNotBlank()) { "Return state binding is required" }
    val nonce = base64UrlEncode(random(16))
    val exp = (clock() + ttlSeconds).toString()
    val mac = base64UrlEncode(sign(nonce, exp, binding))
    return "v1.$nonce.$exp.$mac"
  }

  fun validate(token: String, binding: String): ReturnStatus {
    if (binding.isBlank() || token.length > 512 || token.length < 16) {
      return ReturnStatus.Rejected(ReturnFailure.invalid)
    }
    val parts = token.split('.')
    if (parts.size != 4 || parts[0] != "v1") {
      return ReturnStatus.Rejected(ReturnFailure.invalid)
    }
    val nonce = parts[1]
    val expText = parts[2]
    val signatureText = parts[3]
    val exp = expText.toLongOrNull()
    val signature = base64UrlDecode(signatureText)
    if (nonce.isEmpty() || exp == null || signature == null || expText.any { !it.isDigit() }) {
      return ReturnStatus.Rejected(ReturnFailure.invalid)
    }
    val expected = sign(nonce, expText, binding)
    if (!MessageDigest.isEqual(signature, expected)) {
      return ReturnStatus.Rejected(ReturnFailure.invalid)
    }
    if (!consumed.add(nonce)) {
      return ReturnStatus.Rejected(ReturnFailure.replayed)
    }
    if (clock() >= exp) {
      consumed.remove(nonce)
      return ReturnStatus.Rejected(ReturnFailure.expired)
    }
    return ReturnStatus.Accepted(nonce)
  }

  private fun sign(nonce: String, exp: String, binding: String): ByteArray {
    val mac = Mac.getInstance("HmacSHA256")
    mac.init(SecretKeySpec(secret, "HmacSHA256"))
    return mac.doFinal("v1\n$nonce\n$exp\n$binding".toByteArray(StandardCharsets.UTF_8))
  }

  companion object {
    fun randomSecret(): ByteArray = ByteArray(32).also { SecureRandom().nextBytes(it) }
  }
}

/**
 * Gates a single payment draft. The idempotency key is fixed for the draft.
 * Failed SCA and rejected bank returns leave the key in place and do not submit.
 */
class PaymentAttempt(
  val idempotencyKey: String,
  val method: PaymentMethod,
  private val signer: ReturnStateSigner,
  enrolledPin: String,
) {
  private val enrolledPin = normalizeRehearsalPin(enrolledPin).orEmpty()
  private var outstandingToken: String? = null
  private var cleared = false
  private var completed = false
  private var submitInFlight = false

  var submissionCount: Int = 0
    private set

  val canRetry: Boolean
    get() = cleared && !completed && !submitInFlight

  val isSubmitting: Boolean
    get() = submitInFlight

  fun applySca(biometricAccepted: Boolean, enteredPin: String): ScaDecision {
    if (method != PaymentMethod.card || completed) return ScaDecision.NotRequired
    val decision = if (biometricAccepted) {
      ScaDecision.Confirmed(ScaFactor.biometric)
    } else if (enrolledPin.isNotEmpty() && normalizeRehearsalPin(enteredPin) == enrolledPin) {
      ScaDecision.Confirmed(ScaFactor.pin)
    } else {
      ScaDecision.Rejected
    }
    if (!submitInFlight) {
      cleared = decision is ScaDecision.Confirmed
    }
    return decision
  }

  fun resumeAfterSca(
    biometricAccepted: Boolean,
    enteredPin: String,
    submit: (String) -> Unit,
  ): ScaDecision {
    val decision = applySca(biometricAccepted, enteredPin)
    if (decision is ScaDecision.Confirmed) {
      submitIfCleared(submit)
    }
    return decision
  }

  fun startHandoff(open: (String) -> Boolean): String? {
    if (method != PaymentMethod.bank || completed || submitInFlight) return null
    val token = signer.issue(idempotencyKey)
    val url = BankAllowlist.handoffUrl(token) ?: return null
    if (!BankAllowlist.permitsHandoff(url)) return null
    val opened = BankAllowlist.openIfAllowlisted(url, open)
    if (!opened) return null
    outstandingToken = token
    if (!submitInFlight) cleared = false
    return url
  }

  fun rehearsalReturnUrl(): String? {
    val token = outstandingToken ?: return null
    return BankAllowlist.returnUrl(token)
  }

  fun handleReturn(url: String): ReturnOutcome {
    return when (val intercept = BankAllowlist.intercept(url)) {
      ReturnIntercept.NotReturnLink -> ReturnOutcome.Ignored
      ReturnIntercept.MissingState -> ReturnOutcome.SafeFailure(ReturnFailure.missing, idempotencyKey)
      is ReturnIntercept.Token -> acceptToken(intercept.token)
    }
  }

  fun resumeAfterReturn(url: String, submit: (String) -> Unit): ReturnOutcome {
    val outcome = handleReturn(url)
    if (outcome is ReturnOutcome.Cleared) {
      submitIfCleared(submit)
    }
    return outcome
  }

  fun submitIfCleared(submit: (String) -> Unit): Boolean {
    if (!cleared || completed || submitInFlight) return false
    submitInFlight = true
    submissionCount += 1
    submit(idempotencyKey)
    return true
  }

  fun markCompleted() {
    completed = true
    cleared = false
    submitInFlight = false
    outstandingToken = null
  }

  fun releaseForRetry() {
    if (!completed && cleared) submitInFlight = false
  }

  private fun acceptToken(token: String): ReturnOutcome {
    val matchesOutstanding = token == outstandingToken
    return when (val status = signer.validate(token, idempotencyKey)) {
      is ReturnStatus.Accepted -> {
        if (!matchesOutstanding || completed) {
          ReturnOutcome.SafeFailure(ReturnFailure.invalid, idempotencyKey)
        } else {
          outstandingToken = null
          if (!submitInFlight) cleared = true
          ReturnOutcome.Cleared(idempotencyKey)
        }
      }
      is ReturnStatus.Rejected -> ReturnOutcome.SafeFailure(status.reason, idempotencyKey)
    }
  }
}
