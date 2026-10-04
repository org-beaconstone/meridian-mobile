package com.atlassian.meridian

import java.time.Instant
import java.time.format.DateTimeParseException

/**
 * Local PSD2 SCA step-up for the rehearsal. The verification token is a device-local
 * proof, not a provider cryptogram, credential, or network call.
 */
object Sca {
  const val CODE = "SCA_STEP_UP_REQUIRED"
  const val EUROPEAN_PAYMENT = "Confirm with Face ID / Fingerprint to authorize European payment"
  const val EXPIRED = "This step-up window expired. Start the payment again."
  const val CANCELLED = "Biometric confirmation cancelled. Retry the same payment."
  const val REJECTED = "The authentication challenge was not accepted. Start the payment again."
  const val MALFORMED = "The bank response did not include a usable challenge token. Retry the same payment."
  const val LATENCY = "Local authentication verification exceeded 300 ms. Retry the same payment."
  const val HEADER = "X-Challenge-Verification"
  const val LATENCY_BUDGET_MS = 300L
}

data class ScaChallenge(
  val token: String,
  val expiresAt: Instant,
) {
  fun isExpired(now: Instant): Boolean = !now.isBefore(expiresAt)
}

sealed class ScaAssessment {
  data object NotRequired : ScaAssessment()
  data class Ready(val challenge: ScaChallenge) : ScaAssessment()
  data class Malformed(val message: String) : ScaAssessment()
}

fun interface ScaChallengeHandler {
  /** Present the native biometric dialog. Return true when the user authenticates. */
  suspend fun confirmEuropeanPayment(prompt: String): Boolean
}

fun assessSca(statusCode: Int, body: PaymentResponse): ScaAssessment {
  if (statusCode != 202 || body.code != Sca.CODE) return ScaAssessment.NotRequired
  val token = body.challengeToken
  val expiry = parseScaExpiry(body.challengeExpiresAt)
  if (token.isNullOrEmpty() || expiry == null) return ScaAssessment.Malformed(Sca.MALFORMED)
  return ScaAssessment.Ready(ScaChallenge(token, expiry))
}

fun parseScaExpiry(value: String?): Instant? {
  if (value.isNullOrBlank()) return null
  return try {
    Instant.parse(value)
  } catch (_: DateTimeParseException) {
    null
  }
}

/** FNV-1a 64 of the challenge token. Measured local work must stay under 300 ms. */
fun scaVerificationToken(challengeToken: String): String {
  if (challengeToken.isEmpty()) throw MeridianError.ScaMalformed(Sca.MALFORMED)
  val start = System.nanoTime()
  var hash = 14695981039346656037UL
  val prime = 1099511628211UL
  for (byte in challengeToken.encodeToByteArray()) {
    hash = hash xor byte.toUByte().toULong()
    hash *= prime
  }
  val elapsedMs = (System.nanoTime() - start) / 1_000_000
  if (elapsedMs >= Sca.LATENCY_BUDGET_MS) throw MeridianError.ScaLatencyExceeded(Sca.LATENCY)
  return "sca_v1_${hash.toString(16).padStart(16, '0')}"
}
