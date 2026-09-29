package com.atlassian.meridian

import java.io.Serializable

// MARK: - SCA Challenge Models

/**
 * The authentication method required for an SCA challenge.
 */
enum class SCAType {
  biometric,
  pin,
}

/**
 * An SCA challenge presented before confirming a bank payment.
 *
 * The app layer is responsible for invoking the platform authenticator
 * (e.g. BiometricPrompt on Android) with these parameters.
 */
data class SCAChallenge(
  val paymentId: String,
  val amountMinor: Int,
  val recipientName: String,
  val type: SCAType = SCAType.biometric,
) : Serializable

/**
 * The decoded payload embedded in a bank handoff return URL's state parameter.
 */
data class ReturnState(
  val paymentId: String,
  val nonce: String,
  /** Unix epoch seconds at token creation */
  val issuedAt: Long,
) : Serializable

// MARK: - SCA Callback Interface

/**
 * Callback interface for an SCA authentication attempt.
 * Implement in the app layer using BiometricPrompt.
 */
interface SCACallback {
  /**
   * Called with `success = true` if the user authenticated, `false` if they cancelled or failed.
   * Called with `error` set if a hardware/configuration error occurred.
   */
  fun onResult(success: Boolean, error: String? = null)
}
