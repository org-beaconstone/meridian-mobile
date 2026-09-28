package com.atlassian.meridian

import com.fasterxml.jackson.databind.JsonNode
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/**
 * Local PSD2 step-up for a fictional rehearsal payment.
 *
 * The Java API decides when Strong Customer Authentication applies and answers
 * POST /payments with HTTP 202 and code SCA_STEP_UP_REQUIRED. This handler
 * extracts the challenge payload and expiration, then withholds scaChallengeToken
 * until BiometricPrompt or the in-app passcode succeeds. The resubmit uses the
 * original idempotency key and the original Adyen card or Worldpay bank method.
 * Biometric samples and the passcode never leave the device.
 */
object ScaStepUp {
  const val CODE = "SCA_STEP_UP_REQUIRED"
  const val BIOMETRIC_PROMPT = "Confirm with Face ID / Fingerprint to authorize European payment"
  const val FAILURE_MESSAGE = "Authentication challenge failed. Please verify with your passcode."
}

data class InFlightPayment(
  val recipientId: String,
  val amountMinor: Int,
  val method: PaymentMethod,
  val note: String,
  val scenario: Scenario,
  val idempotencyKey: String,
)

data class ScaChallenge(
  val payload: String,
  val expiresAtEpochMs: Long,
  val scaChallengeToken: String,
)

data class ScaResubmission(
  val recipientId: String,
  val amountMinor: Int,
  val method: PaymentMethod,
  val note: String,
  val scenario: Scenario,
  val idempotencyKey: String,
  val scaChallengeToken: String,
)

sealed class ScaPhase {
  data class Biometric(val challenge: ScaChallenge) : ScaPhase()
  data class Passcode(val challenge: ScaChallenge, val message: String?) : ScaPhase()
  data class Ready(val challenge: ScaChallenge) : ScaPhase()
  data class Failed(val message: String) : ScaPhase()
}

data class ScaChallengeHandler(
  val payment: InFlightPayment,
  val phase: ScaPhase,
) {
  /** Null when the response is not an HTTP 202 step-up. Expired or incomplete challenges fail closed. */
  companion object {
    fun begin(
      statusCode: Int,
      body: PaymentResponse,
      payment: InFlightPayment,
      nowEpochMs: Long,
    ): ScaChallengeHandler? {
      if (statusCode != 202 || body.code != ScaStepUp.CODE) return null
      val challenge = extract(body)
      if (challenge == null || challenge.expiresAtEpochMs <= nowEpochMs) {
        return ScaChallengeHandler(payment, ScaPhase.Failed(ScaStepUp.FAILURE_MESSAGE))
      }
      return ScaChallengeHandler(payment, ScaPhase.Biometric(challenge))
    }
  }

  fun biometricUnavailableOrFailed(nowEpochMs: Long): ScaChallengeHandler {
    val challenge = (phase as? ScaPhase.Biometric)?.challenge ?: return this
    if (challenge.expiresAtEpochMs <= nowEpochMs) {
      return copy(phase = ScaPhase.Failed(ScaStepUp.FAILURE_MESSAGE))
    }
    return copy(phase = ScaPhase.Passcode(challenge, null))
  }

  fun biometricSucceeded(nowEpochMs: Long): ScaChallengeHandler {
    val challenge = (phase as? ScaPhase.Biometric)?.challenge ?: return this
    if (challenge.expiresAtEpochMs <= nowEpochMs) {
      return copy(phase = ScaPhase.Failed(ScaStepUp.FAILURE_MESSAGE))
    }
    return copy(phase = ScaPhase.Ready(challenge))
  }

  fun passcodeVerified(nowEpochMs: Long): ScaChallengeHandler {
    val challenge = (phase as? ScaPhase.Passcode)?.challenge ?: return this
    if (challenge.expiresAtEpochMs <= nowEpochMs) {
      return copy(phase = ScaPhase.Failed(ScaStepUp.FAILURE_MESSAGE))
    }
    return copy(phase = ScaPhase.Ready(challenge))
  }

  fun passcodeRejected(nowEpochMs: Long): ScaChallengeHandler {
    val challenge = (phase as? ScaPhase.Passcode)?.challenge ?: return this
    if (challenge.expiresAtEpochMs <= nowEpochMs) {
      return copy(phase = ScaPhase.Failed(ScaStepUp.FAILURE_MESSAGE))
    }
    return copy(phase = ScaPhase.Passcode(challenge, ScaStepUp.FAILURE_MESSAGE))
  }

  /** Token is released only after biometric or passcode success, on the original key and method. */
  fun resubmission(): ScaResubmission? {
    val challenge = (phase as? ScaPhase.Ready)?.challenge ?: return null
    return ScaResubmission(
      recipientId = payment.recipientId,
      amountMinor = payment.amountMinor,
      method = payment.method,
      note = payment.note,
      scenario = payment.scenario,
      idempotencyKey = payment.idempotencyKey,
      scaChallengeToken = challenge.scaChallengeToken,
    )
  }
}

object RehearsalPasscode {
  fun isWellFormed(value: String): Boolean = value.length == 6 && value.all { it.isDigit() }

  /** Local comparison only. The passcode is not part of the payment body. */
  fun matches(entered: String, enrolled: String): Boolean {
    if (!isWellFormed(entered) || !isWellFormed(enrolled)) return false
    var diff = 0
    for (index in entered.indices) {
      diff = diff or (entered[index].code xor enrolled[index].code)
    }
    return diff == 0
  }
}

internal fun parseScaTimestamp(raw: String): Long? {
  val value = normalizeScaTimestamp(raw.trim())
  val patterns = arrayOf(
    "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
    "yyyy-MM-dd'T'HH:mm:ssXXX",
  )
  for (pattern in patterns) {
    try {
      val format = SimpleDateFormat(pattern, Locale.US)
      format.timeZone = TimeZone.getTimeZone("UTC")
      format.isLenient = false
      val parsed = format.parse(value) ?: continue
      return parsed.time
    } catch (_: Exception) {
      // Try the next pattern. Fractional and whole-second forms both occur.
    }
  }
  return null
}

private fun normalizeScaTimestamp(raw: String): String {
  var value = raw
  if (value.endsWith("Z")) value = value.dropLast(1) + "+00:00"
  val match = Regex("""^(.*T\d{2}:\d{2}:\d{2})(?:\.(\d+))?([+-]\d{2}:\d{2})$""").matchEntire(value)
    ?: return value
  val fraction = match.groupValues[2]
  val fractional = if (fraction.isEmpty()) "" else "." + fraction.padEnd(3, '0').take(3)
  return match.groupValues[1] + fractional + match.groupValues[3]
}

private fun extract(body: PaymentResponse): ScaChallenge? {
  val challenge = body.challenge
  val payload = when {
    challenge == null -> null
    challenge.isTextual -> challenge.asText().trim().ifEmpty { null }
    challenge.isObject -> text(challenge, "payload")
    else -> null
  } ?: body.challengePayload?.trim()?.ifEmpty { null }

  val expiresRaw = when {
    challenge != null && challenge.isObject ->
      text(challenge, "expiresAt")
        ?: text(challenge, "expirationTimestamp")
        ?: text(challenge, "expiration")
    else -> null
  } ?: body.expiresAt?.trim()?.ifEmpty { null }
    ?: body.expirationTimestamp?.trim()?.ifEmpty { null }
    ?: body.expiration?.trim()?.ifEmpty { null }

  val token = when {
    challenge != null && challenge.isObject ->
      text(challenge, "scaChallengeToken") ?: text(challenge, "token")
    else -> null
  } ?: body.scaChallengeToken?.trim()?.ifEmpty { null }

  val expiresAt = expiresRaw?.let(::parseScaTimestamp) ?: return null
  if (payload == null || token == null) return null
  return ScaChallenge(payload, expiresAt, token)
}

private fun text(node: JsonNode, field: String): String? {
  if (!node.has(field) || node.get(field).isNull) return null
  return node.get(field).asText().trim().ifEmpty { null }
}
