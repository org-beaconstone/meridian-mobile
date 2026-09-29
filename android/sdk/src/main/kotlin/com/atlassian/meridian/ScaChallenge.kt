package com.atlassian.meridian

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import java.text.ParseException
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/**
 * PSD2 Strong Customer Authentication for a European payment.
 * The rehearsal passcode is compared on device and is never sent to the API or a provider.
 */
object ScaCopy {
  const val STEP_UP_CODE = "SCA_STEP_UP_REQUIRED"
  const val BIOMETRIC_PROMPT = "Confirm with Face ID / Fingerprint to authorize European payment"
  const val FAILURE_MESSAGE = "Authentication challenge failed. Please verify with your passcode."
  const val REHEARSAL_PASSCODE = "135790"
}

enum class BiometricStatus {
  SUCCESS,
  FAILED,
  UNAVAILABLE,
  CANCELLED,
}

enum class ScaPhase {
  BIOMETRIC,
  PASSCODE,
  READY,
  FAILED,
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
  val token: String?,
) {
  fun isExpired(nowMs: Long): Boolean = nowMs >= expiresAtMs

  fun resubmitToken(): String = token?.takeIf { it.isNotEmpty() } ?: payload
}

sealed class ScaIntercept {
  data object NotStepUp : ScaIntercept()
  data object Invalid : ScaIntercept()
  data class Expired(val challenge: ScaChallenge) : ScaIntercept()
  data class Required(val challenge: ScaChallenge) : ScaIntercept()
}

data class ScaResubmit(
  val recipientId: String,
  val amountMinor: Int,
  val method: PaymentMethod,
  val note: String,
  val scenario: Scenario,
  val idempotencyKey: String,
  val scaChallengeToken: String,
)

data class ScaSession(
  val draft: PaymentDraft,
  val challenge: ScaChallenge,
  val phase: ScaPhase,
  val token: String? = null,
  val message: String? = null,
) {
  val showsPasscode: Boolean
    get() = phase == ScaPhase.PASSCODE || phase == ScaPhase.FAILED

  fun resubmit(): ScaResubmit? {
    if (phase != ScaPhase.READY || token.isNullOrEmpty()) return null
    return ScaResubmit(
      recipientId = draft.recipientId,
      amountMinor = draft.amountMinor,
      method = draft.method,
      note = draft.note,
      scenario = draft.scenario,
      idempotencyKey = draft.idempotencyKey,
      scaChallengeToken = token,
    )
  }

  fun afterBiometric(status: BiometricStatus, nowMs: Long = System.currentTimeMillis()): ScaSession {
    if (phase != ScaPhase.BIOMETRIC) return this
    if (challenge.isExpired(nowMs)) return failed()
    if (status == BiometricStatus.SUCCESS) {
      return copy(phase = ScaPhase.READY, token = challenge.resubmitToken(), message = null)
    }
    return copy(phase = ScaPhase.PASSCODE, token = null, message = null)
  }

  fun afterPasscode(
    entered: String,
    nowMs: Long = System.currentTimeMillis(),
    expected: String = ScaCopy.REHEARSAL_PASSCODE,
  ): ScaSession {
    if (phase != ScaPhase.PASSCODE && phase != ScaPhase.FAILED) return this
    if (challenge.isExpired(nowMs)) return failed()
    if (ScaPasscode.matches(entered, expected)) {
      return copy(phase = ScaPhase.READY, token = challenge.resubmitToken(), message = null)
    }
    return failed()
  }

  private fun failed(): ScaSession =
    copy(phase = ScaPhase.FAILED, token = null, message = ScaCopy.FAILURE_MESSAGE)

  companion object {
    fun start(draft: PaymentDraft, challenge: ScaChallenge, nowMs: Long = System.currentTimeMillis()): ScaSession {
      if (challenge.isExpired(nowMs)) {
        return ScaSession(draft, challenge, ScaPhase.FAILED, message = ScaCopy.FAILURE_MESSAGE)
      }
      return ScaSession(draft, challenge, ScaPhase.BIOMETRIC)
    }
  }
}

object ScaPasscode {
  fun matches(entered: String, expected: String): Boolean {
    if (entered.length != expected.length || expected.isEmpty()) return false
    var diff = 0
    for (index in expected.indices) {
      diff = diff or (entered[index].code xor expected[index].code)
    }
    return diff == 0
  }
}

object ScaInterpreter {
  private val mapper = ObjectMapper()
  private val expiryKeys = listOf("expiresAt", "expirationTimestamp", "expiration", "expiry")
  private val payloadKeys = listOf("payload", "challengePayload")
  private val tokenKeys = listOf("scaChallengeToken", "token")

  /**
   * HTTP 202 with `SCA_STEP_UP_REQUIRED` is the only step-up signal.
   * A pending payment uses the same status with a different code.
   */
  fun interpret(statusCode: Int, body: String, nowMs: Long = System.currentTimeMillis()): ScaIntercept {
    if (statusCode != 202) return ScaIntercept.NotStepUp
    val root = try {
      mapper.readTree(body)
    } catch (_: Exception) {
      return ScaIntercept.NotStepUp
    }
    if (!root.isObject || root.path("code").asText() != ScaCopy.STEP_UP_CODE) {
      return ScaIntercept.NotStepUp
    }
    val challenge = extract(root) ?: return ScaIntercept.Invalid
    if (challenge.isExpired(nowMs)) return ScaIntercept.Expired(challenge)
    return ScaIntercept.Required(challenge)
  }

  private fun extract(root: JsonNode): ScaChallenge? {
    val nested = objectOrNull(root.get("challenge")) ?: objectOrNull(root.get("scaChallenge"))
    val payload = text(nested, payloadKeys)
      ?: text(root, payloadKeys)
      ?: root.get("challenge")?.takeIf { it.isTextual }?.asText()?.trim()?.takeIf { it.isNotEmpty() }
    val expiresAtMs = expiry(nested) ?: expiry(root)
    if (payload.isNullOrEmpty() || expiresAtMs == null) return null
    val token = text(nested, tokenKeys) ?: text(root, tokenKeys)
    return ScaChallenge(payload, expiresAtMs, token)
  }

  private fun objectOrNull(node: JsonNode?): JsonNode? =
    if (node != null && node.isObject) node else null

  private fun text(node: JsonNode?, keys: List<String>): String? {
    if (node == null) return null
    for (key in keys) {
      val value = node.get(key) ?: continue
      if (!value.isTextual) continue
      val trimmed = value.asText().trim()
      if (trimmed.isNotEmpty()) return trimmed
    }
    return null
  }

  private fun expiry(node: JsonNode?): Long? {
    if (node == null) return null
    for (key in expiryKeys) {
      val parsed = parseExpiry(node.get(key))
      if (parsed != null) return parsed
    }
    return null
  }

  private fun parseExpiry(node: JsonNode?): Long? {
    if (node == null || node.isNull || node.isMissingNode) return null
    if (node.isNumber) {
      val raw = node.asDouble()
      if (!raw.isFinite() || raw <= 0.0) return null
      return if (raw > 10_000_000_000.0) raw.toLong() else (raw * 1000.0).toLong()
    }
    if (!node.isTextual) return null
    return parseTimestamp(node.asText().trim())
  }

  private fun parseTimestamp(text: String): Long? {
    if (text.isEmpty()) return null
    val patterns = arrayOf(
      "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
      "yyyy-MM-dd'T'HH:mm:ssXXX",
      "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
      "yyyy-MM-dd'T'HH:mm:ss'Z'",
    )
    for (pattern in patterns) {
      val parsed = try {
        val format = SimpleDateFormat(pattern, Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        format.isLenient = false
        format.parse(text)?.time
      } catch (_: ParseException) {
        null
      }
      if (parsed != null) return parsed
    }
    return null
  }
}
