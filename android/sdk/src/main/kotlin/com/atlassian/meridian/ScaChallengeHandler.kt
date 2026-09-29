package com.atlassian.meridian

import java.time.Instant

// MARK: - Protocols

/**
 * Abstraction over native biometric authentication.
 *
 * Production implementations should use `androidx.biometric.BiometricPrompt` inside a
 * `FragmentActivity`. Inject a test double for unit tests.
 */
interface ScaBiometricAuthenticator {
  /** Returns `true` when the device can perform biometric authentication right now. */
  fun canAuthenticate(): Boolean

  /**
   * Presents the native biometric prompt with [prompt] as the description.
   * Returns `true` on success, `false` on denial; throws on a hard error.
   */
  suspend fun authenticate(prompt: String): Boolean
}

/**
 * Abstraction over in-app passcode verification, presented when biometrics are
 * unavailable or the customer's biometric attempt fails.
 */
interface ScaPasscodeVerifier {
  /** Presents the in-app passcode challenge. Returns `true` on success. */
  suspend fun verifyPasscode(): Boolean
}

// MARK: - SCA Challenge Handler

/**
 * Handles PSD2 SCA step-up authentication invoked when the payment gateway
 * returns HTTP 202 with `SCA_STEP_UP_REQUIRED`.
 *
 * Flow:
 * 1. Check the challenge has not expired.
 * 2. Attempt native biometric authentication.
 * 3. On biometric failure or unavailability, fall back to in-app passcode.
 * 4. On successful authentication, re-dispatch the original payment payload
 *    with `scaChallengeToken` under the original idempotency key.
 */
class ScaChallengeHandler(
  private val client: MeridianClient,
  private val biometricAuthenticator: ScaBiometricAuthenticator,
  private val passcodeVerifier: ScaPasscodeVerifier,
) {
  companion object {
    const val BIOMETRIC_PROMPT =
      "Confirm with Face ID / Fingerprint to authorize European payment"
    const val FAILURE_MESSAGE =
      "Authentication challenge failed. Please verify with your passcode."
  }

  /**
   * Handle an `SCA_STEP_UP_REQUIRED` response and complete the payment.
   *
   * @param scaChallengeToken Token extracted from the gateway `SCA_STEP_UP_REQUIRED` response.
   * @param challengeExpiresAt ISO 8601 expiration timestamp from the challenge response.
   * @param recipientId Original payment recipient ID.
   * @param amountMinor Original payment amount in GBP pence.
   * @param method Original payment method.
   * @param note Original payment note / reference.
   * @param scenario Original simulation scenario.
   * @param idempotencyKey Original idempotency key – reused so the gateway can correlate
   *   the re-dispatch with the initial attempt.
   */
  suspend fun handle(
    scaChallengeToken: String,
    challengeExpiresAt: String,
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String,
    scenario: Scenario,
    idempotencyKey: String,
  ): ScaOutcome {
    // 1. Guard: challenge must not already be expired
    if (isExpired(challengeExpiresAt)) {
      return ScaOutcome.ChallengeExpired(FAILURE_MESSAGE)
    }

    // 2. Authenticate – biometrics first, passcode fallback
    val authenticated = attemptAuthentication()
    if (!authenticated) {
      return ScaOutcome.AuthenticationFailed(FAILURE_MESSAGE)
    }

    // 3. Re-check expiry: authentication may have taken time
    if (isExpired(challengeExpiresAt)) {
      return ScaOutcome.ChallengeExpired(FAILURE_MESSAGE)
    }

    // 4. Re-dispatch payment with scaChallengeToken under the original idempotency key
    return try {
      val response = client.submitScaPayment(
        recipientId = recipientId,
        amountMinor = amountMinor,
        method = method,
        note = note,
        scenario = scenario,
        idempotencyKey = idempotencyKey,
        scaChallengeToken = scaChallengeToken,
      )
      ScaOutcome.Success(response)
    } catch (e: Exception) {
      ScaOutcome.AuthenticationFailed(FAILURE_MESSAGE)
    }
  }

  // MARK: - Helpers

  private fun isExpired(expiresAt: String): Boolean {
    return try {
      val expiry = Instant.parse(expiresAt)
      expiry.toEpochMilli() <= System.currentTimeMillis()
    } catch (e: Exception) {
      false // Unparseable timestamp: don't treat as expired
    }
  }

  private suspend fun attemptAuthentication(): Boolean {
    if (biometricAuthenticator.canAuthenticate()) {
      try {
        if (biometricAuthenticator.authenticate(BIOMETRIC_PROMPT)) {
          return true
        }
      } catch (e: Exception) {
        // Biometric attempt failed; fall through to passcode verifier
      }
    }
    return passcodeVerifier.verifyPasscode()
  }
}
