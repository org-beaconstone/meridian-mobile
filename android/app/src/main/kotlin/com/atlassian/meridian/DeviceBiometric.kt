package com.atlassian.meridian

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

internal fun biometricAuthenticators(activity: FragmentActivity): Int? {
  val manager = BiometricManager.from(activity)
  val strong = BiometricManager.Authenticators.BIOMETRIC_STRONG
  if (manager.canAuthenticate(strong) == BiometricManager.BIOMETRIC_SUCCESS) return strong
  val weak = BiometricManager.Authenticators.BIOMETRIC_WEAK
  if (manager.canAuthenticate(weak) == BiometricManager.BIOMETRIC_SUCCESS) return weak
  return null
}

/** Device biometric prompt. A failure, bypass, or unavailable result stays inside Meridian. */
internal fun launchInAppBiometric(
  activity: FragmentActivity,
  onResult: (BiometricOutcome?) -> Unit,
) {
  val authenticators = biometricAuthenticators(activity)
  if (authenticators == null) {
    onResult(BiometricOutcome.unavailable)
    return
  }
  val executor = ContextCompat.getMainExecutor(activity)
  val prompt = BiometricPrompt(
    activity,
    executor,
    object : BiometricPrompt.AuthenticationCallback() {
      override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
        onResult(BiometricOutcome.succeeded)
      }

      override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
        when (errorCode) {
          BiometricPrompt.ERROR_NEGATIVE_BUTTON -> onResult(BiometricOutcome.bypassed)
          BiometricPrompt.ERROR_USER_CANCELED,
          BiometricPrompt.ERROR_CANCELED -> onResult(null)
          BiometricPrompt.ERROR_HW_NOT_PRESENT,
          BiometricPrompt.ERROR_HW_UNAVAILABLE,
          BiometricPrompt.ERROR_NO_BIOMETRICS -> onResult(BiometricOutcome.unavailable)
          else -> onResult(BiometricOutcome.rejected)
        }
      }
    },
  )
  val info = BiometricPrompt.PromptInfo.Builder()
    .setTitle("Confirm it's you")
    .setSubtitle("This check stays in Meridian")
    .setNegativeButtonText("Use passcode")
    .setAllowedAuthenticators(authenticators)
    .build()
  prompt.authenticate(info)
}
