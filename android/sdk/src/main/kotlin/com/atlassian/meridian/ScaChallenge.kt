package com.atlassian.meridian

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import java.util.Calendar
import java.util.GregorianCalendar
import java.util.TimeZone

/**
 * Local PSD2 step-up for a fictional rehearsal payment.
 *
 * HTTP 202 with `SCA_STEP_UP_REQUIRED` carries the challenge payload and expiration.
 * The original recipient, integer pence amount, Adyen card or Worldpay bank method,
 * and idempotency key stay in place. `scaChallengeToken` is added only after
 * BiometricPrompt or the in-app passcode succeeds. The passcode is not sent.
 */
object ScaCopy {
  const val STEP_UP_CODE = "SCA_STEP_UP_REQUIRED"
  const val BIOMETRIC_PROMPT = "Confirm with Face ID / Fingerprint to authorize European payment"
  const val FAILURE_MESSAGE = "Authentication challenge failed. Please verify with your passcode."
  /** Fictional rehearsal passcode. Compared on device only. */
  const val REHEARSAL_PASSCODE = "135790"
}

enum class BiometricStatus {
  SUCCESS, FAILED, UNAVAILABLE, CANCELLED
}

data class PaymentDraft(
  val recipientId: String,
  val amountMinor: Int,
  val method: PaymentMethod,
  val note: String,
  val scenario: Scenario,
  val idempotencyKey: String,
)

data class ScaChallenge(
  val payload: String,
  val expiresAtMs: Long,
  val token: String? = null,
) {
  fun isExpired(nowMs: Long = System.currentTimeMillis()): Boolean = nowMs >= expiresAtMs

  /** Explicit gateway token when present; otherwise the challenge payload is echoed back. */
  fun tokenForResubmit(): String = token?.takeIf { it.isNotEmpty() } ?: payload
}

sealed class ScaIntercept {
  data object NotStepUp : ScaIntercept()
  data object Invalid : ScaIntercept()
  data class Expired(val challenge: ScaChallenge) : ScaIntercept()
  data class Required(val challenge: ScaChallenge) : ScaIntercept()
}

enum class ScaPhase {
  BIOMETRIC, PASSCODE, READY, FAILED
}

data class ScaSession(
  val draft: PaymentDraft,
  val challenge: ScaChallenge,
  val phase: ScaPhase,
  val message: String? = null,
) {
  val resubmitToken: String?
    get() = if (phase == ScaPhase.READY) challenge.tokenForResubmit() else null

  val showsPasscode: Boolean
    get() = phase == ScaPhase.PASSCODE || phase == ScaPhase.FAILED

  companion object {
    fun start(draft: PaymentDraft, challenge: ScaChallenge, nowMs: Long = System.currentTimeMillis()): ScaSession {
      if (challenge.isExpired(nowMs)) {
        return ScaSession(draft, challenge, ScaPhase.FAILED, ScaCopy.FAILURE_MESSAGE)
      }
      return ScaSession(draft, challenge, ScaPhase.BIOMETRIC, null)
    }
  }

  fun afterBiometric(status: BiometricStatus, nowMs: Long = System.currentTimeMillis()): ScaSession {
    if (phase != ScaPhase.BIOMETRIC) return this
    if (challenge.isExpired(nowMs)) return copy(phase = ScaPhase.FAILED, message = ScaCopy.FAILURE_MESSAGE)
    return if (status == BiometricStatus.SUCCESS) {
      copy(phase = ScaPhase.READY, message = null)
    } else {
      copy(phase = ScaPhase.PASSCODE, message = null)
    }
  }

  fun afterPasscode(
    entered: String,
    nowMs: Long = System.currentTimeMillis(),
    expected: String = ScaCopy.REHEARSAL_PASSCODE,
  ): ScaSession {
    if (phase != ScaPhase.PASSCODE && phase != ScaPhase.FAILED) return this
    if (challenge.isExpired(nowMs)) return copy(phase = ScaPhase.FAILED, message = ScaCopy.FAILURE_MESSAGE)
    return if (RehearsalPasscode.matches(entered, expected)) {
      copy(phase = ScaPhase.READY, message = null)
    } else {
      copy(phase = ScaPhase.FAILED, message = ScaCopy.FAILURE_MESSAGE)
    }
  }
}

object RehearsalPasscode {
  fun matches(entered: String, expected: String = ScaCopy.REHEARSAL_PASSCODE): Boolean {
    if (entered.length != 6 || expected.length != 6 || entered.any { !it.isDigit() }) return false
    var diff = 0
    for (index in entered.indices) {
      diff = diff or (entered[index].code xor expected[index].code)
    }
    return diff == 0
  }
}

object ScaInterpreter {
  private val mapper = ObjectMapper()

  /**
   * HTTP 202 plus `SCA_STEP_UP_REQUIRED` is the only step-up signal.
   * `PAYMENT_PENDING` stays a normal pending result.
   */
  fun intercept(statusCode: Int, body: String, nowMs: Long = System.currentTimeMillis()): ScaIntercept {
    if (statusCode != 202) return ScaIntercept.NotStepUp
    val root = try {
      mapper.readTree(body)
    } catch (_: Exception) {
      return ScaIntercept.NotStepUp
    }
    if (!root.isObject || root.path("code").asText() != ScaCopy.STEP_UP_CODE) return ScaIntercept.NotStepUp
    val challenge = extract(root) ?: return ScaIntercept.Invalid
    if (challenge.isExpired(nowMs)) return ScaIntercept.Expired(challenge)
    return ScaIntercept.Required(challenge)
  }
}

private fun extract(root: JsonNode): ScaChallenge? {
  val nested = root.path("challenge").takeIf { it.isObject } ?: root.path("scaChallenge").takeIf { it.isObject }
  val payload = firstText(nested, "payload", "challengePayload")
    ?: firstText(root, "challengePayload", "payload")
    ?: return null
  val expiresAt = firstTime(nested, "expiresAt", "expiration", "expirationTimestamp", "expiry")
    ?: firstTime(root, "expiresAt", "expiration", "expirationTimestamp", "expiry")
    ?: return null
  val token = firstText(nested, "scaChallengeToken", "token") ?: firstText(root, "scaChallengeToken", "token")
  return ScaChallenge(payload, expiresAt, token)
}

private fun firstText(node: JsonNode?, vararg keys: String): String? {
  if (node == null || node.isMissingNode || node.isNull) return null
  for (key in keys) {
    val value = node.path(key)
    if (value.isTextual) {
      val trimmed = value.asText().trim()
      if (trimmed.isNotEmpty()) return trimmed
    }
  }
  return null
}

private fun firstTime(node: JsonNode?, vararg keys: String): Long? {
  if (node == null || node.isMissingNode || node.isNull) return null
  for (key in keys) {
    val value = node.path(key)
    if (value.isMissingNode || value.isNull) continue
    parseScaTimestamp(value)?.let { return it }
  }
  return null
}

internal fun parseScaTimestamp(node: JsonNode): Long? {
  if (node.isNumber) {
    val raw = node.asLong()
    return if (raw > 10_000_000_000L) raw else raw * 1000
  }
  if (node.isTextual) return parseScaTimestamp(node.asText())
  return null
}

internal fun parseScaTimestamp(raw: String): Long? {
  val text = raw.trim()
  val match = Regex(
    """^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|[+-]\d{2}:\d{2})$"""
  ).matchEntire(text) ?: return null
  val year = match.groupValues[1].toInt()
  val month = match.groupValues[2].toInt()
  val day = match.groupValues[3].toInt()
  val hour = match.groupValues[4].toInt()
  val minute = match.groupValues[5].toInt()
  val second = match.groupValues[6].toInt()
  val fraction = match.groupValues[7]
  val zone = match.groupValues[8]
  val millis = if (fraction.isEmpty()) 0 else fraction.padEnd(3, '0').take(3).toInt()
  val calendar = GregorianCalendar(TimeZone.getTimeZone("UTC")).apply {
    isLenient = false
    set(Calendar.YEAR, year)
    set(Calendar.MONTH, month - 1)
    set(Calendar.DAY_OF_MONTH, day)
    set(Calendar.HOUR_OF_DAY, hour)
    set(Calendar.MINUTE, minute)
    set(Calendar.SECOND, second)
    set(Calendar.MILLISECOND, millis)
  }
  val base = try {
    calendar.timeInMillis
  } catch (_: IllegalArgumentException) {
    return null
  }
  val offsetMs = when (zone) {
    "Z" -> 0
    else -> {
      val sign = if (zone.startsWith("-")) -1 else 1
      val parts = zone.drop(1).split(":")
      sign * ((parts[0].toInt() * 60) + parts[1].toInt()) * 60_000
    }
  }
  return base - offsetMs
}
