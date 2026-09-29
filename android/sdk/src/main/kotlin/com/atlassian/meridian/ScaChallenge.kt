package com.atlassian.meridian

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import java.time.Instant
import java.time.OffsetDateTime

/**
 * PSD2 Strong Customer Authentication copy and the fictional in-app passcode.
 * The passcode is checked on device only and is never sent to the API or a provider.
 */
object ScaCopy {
  const val STEP_UP_CODE = "SCA_STEP_UP_REQUIRED"
  const val BIOMETRIC_PROMPT = "Confirm with Face ID / Fingerprint to authorize European payment"
  const val FAILURE_MESSAGE = "Authentication challenge failed. Please verify with your passcode."
  const val REHEARSAL_PASSCODE = "135790"
}

enum class BiometricStatus {
  SUCCESS, FAILED, UNAVAILABLE, CANCELLED
}

fun interface DeviceBiometric {
  suspend fun authenticate(prompt: String): BiometricStatus
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
  val expiresAt: Instant,
  val token: String? = null,
) {
  val resubmitToken: String
    get() = token?.takeIf { it.isNotEmpty() } ?: payload

  fun isExpired(now: Instant = Instant.now()): Boolean = !expiresAt.isAfter(now)
}

sealed class ScaIntercept {
  data object NotStepUp : ScaIntercept()
  data object Invalid : ScaIntercept()
  data class Expired(val challenge: ScaChallenge) : ScaIntercept()
  data class Required(val challenge: ScaChallenge) : ScaIntercept()
}

object ScaInterpreter {
  private val mapper = ObjectMapper().registerKotlinModule()

  fun intercept(statusCode: Int, bodyText: String, now: Instant = Instant.now()): ScaIntercept {
    if (statusCode != 202) return ScaIntercept.NotStepUp
    val root = try {
      mapper.readTree(bodyText)
    } catch (_: Exception) {
      return ScaIntercept.NotStepUp
    }
    if (!root.isObject || root.path("code").asText() != ScaCopy.STEP_UP_CODE) return ScaIntercept.NotStepUp
    val challenge = extract(root) ?: return ScaIntercept.Invalid
    return if (challenge.isExpired(now)) ScaIntercept.Expired(challenge) else ScaIntercept.Required(challenge)
  }

  fun extract(root: JsonNode): ScaChallenge? {
    val nested = root.get("challenge")?.takeIf { it.isObject }
      ?: root.get("scaChallenge")?.takeIf { it.isObject }
    val payload = nested?.let { text(it, "payload") ?: text(it, "challengePayload") }
      ?: text(root, "challengePayload")
      ?: text(root, "payload")
    val expires = nested?.let { expiry(it) } ?: expiry(root)
    if (payload == null || expires == null) return null
    val token = nested?.let { text(it, "token") ?: text(it, "scaChallengeToken") }
      ?: text(root, "scaChallengeToken")
    return ScaChallenge(payload, expires, token)
  }

  private fun text(node: JsonNode, key: String): String? {
    val value = node.get(key) ?: return null
    if (!value.isTextual) return null
    return value.asText().takeIf { it.isNotEmpty() }
  }

  private fun expiry(node: JsonNode): Instant? {
    val value = node.get("expiresAt") ?: node.get("expiration") ?: node.get("expiry") ?: return null
    return parseExpiry(value)
  }

  private fun parseExpiry(value: JsonNode): Instant? {
    if (value.isTextual) {
      val text = value.asText()
      return try {
        Instant.parse(text)
      } catch (_: Exception) {
        try {
          OffsetDateTime.parse(text).toInstant()
        } catch (_: Exception) {
          null
        }
      }
    }
    if (value.isNumber) {
      val raw = value.asLong()
      return if (raw > 10_000_000_000L) Instant.ofEpochMilli(raw) else Instant.ofEpochSecond(raw)
    }
    return null
  }
}

sealed class ScaPhase {
  data object Biometric : ScaPhase()
  data object Passcode : ScaPhase()
  data class Ready(val token: String) : ScaPhase()
  data class Failed(val message: String) : ScaPhase()
}

data class ScaSession(
  val draft: PaymentDraft,
  val challenge: ScaChallenge,
  val phase: ScaPhase,
) {
  val showsPasscode: Boolean
    get() = phase is ScaPhase.Passcode || phase is ScaPhase.Failed

  val resubmitToken: String?
    get() = (phase as? ScaPhase.Ready)?.token

  fun afterBiometric(status: BiometricStatus, now: Instant = Instant.now()): ScaSession {
    if (phase !is ScaPhase.Biometric) return this
    if (challenge.isExpired(now)) return copy(phase = ScaPhase.Failed(ScaCopy.FAILURE_MESSAGE))
    val next = if (status == BiometricStatus.SUCCESS) {
      ScaPhase.Ready(challenge.resubmitToken)
    } else {
      ScaPhase.Passcode
    }
    return copy(phase = next)
  }

  fun afterPasscode(
    entered: String,
    now: Instant = Instant.now(),
    expected: String = ScaCopy.REHEARSAL_PASSCODE,
  ): ScaSession {
    if (phase !is ScaPhase.Passcode && phase !is ScaPhase.Failed) return this
    if (challenge.isExpired(now)) return copy(phase = ScaPhase.Failed(ScaCopy.FAILURE_MESSAGE))
    val next = if (entered == expected) {
      ScaPhase.Ready(challenge.resubmitToken)
    } else {
      ScaPhase.Failed(ScaCopy.FAILURE_MESSAGE)
    }
    return copy(phase = next)
  }

  companion object {
    fun start(draft: PaymentDraft, challenge: ScaChallenge, now: Instant = Instant.now()): ScaSession {
      val phase = if (challenge.isExpired(now)) {
        ScaPhase.Failed(ScaCopy.FAILURE_MESSAGE)
      } else {
        ScaPhase.Biometric
      }
      return ScaSession(draft, challenge, phase)
    }
  }
}
