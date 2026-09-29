package com.atlassian.meridian

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.fragment.app.FragmentActivity
import java.util.concurrent.Executor
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Android BiometricPrompt for the PSD2 step-up.
 * Device credential is not accepted here. Failure or unavailability continues
 * into the in-app passcode challenge without changing the payment.
 */
class AndroidBiometricAuthenticator(
  private val activity: FragmentActivity,
) {
  suspend fun authenticate(prompt: String): BiometricStatus {
    val authenticators = BiometricManager.Authenticators.BIOMETRIC_STRONG
    val can = try {
      BiometricManager.from(activity).canAuthenticate(authenticators)
    } catch (_: Exception) {
      return BiometricStatus.UNAVAILABLE
    }
    if (can != BiometricManager.BIOMETRIC_SUCCESS) return BiometricStatus.UNAVAILABLE

    return suspendCancellableCoroutine { continuation ->
      val executor = Executor { command -> activity.runOnUiThread(command) }
      val callback = object : BiometricPrompt.AuthenticationCallback() {
        override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
          if (continuation.isActive) continuation.resume(BiometricStatus.SUCCESS)
        }

        override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
          if (!continuation.isActive) return
          val status = when (errorCode) {
            BiometricPrompt.ERROR_HW_NOT_PRESENT,
            BiometricPrompt.ERROR_HW_UNAVAILABLE,
            BiometricPrompt.ERROR_NO_BIOMETRICS,
            BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL,
            BiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED,
            BiometricPrompt.ERROR_LOCKOUT,
            BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> BiometricStatus.UNAVAILABLE
            BiometricPrompt.ERROR_USER_CANCELED,
            BiometricPrompt.ERROR_NEGATIVE_BUTTON,
            BiometricPrompt.ERROR_CANCELED -> BiometricStatus.CANCELLED
            else -> BiometricStatus.FAILED
          }
          continuation.resume(status)
        }

        override fun onAuthenticationFailed() {
          // A single unrecognized biometric stays on the system sheet.
          // Terminal failure arrives through onAuthenticationError.
        }
      }
      val promptUi = BiometricPrompt(activity, executor, callback)
      val info = BiometricPrompt.PromptInfo.Builder()
        .setTitle(prompt)
        .setAllowedAuthenticators(authenticators)
        .setNegativeButtonText("Use passcode")
        .build()
      continuation.invokeOnCancellation { promptUi.cancelAuthentication() }
      try {
        promptUi.authenticate(info)
      } catch (_: Exception) {
        if (continuation.isActive) continuation.resume(BiometricStatus.UNAVAILABLE)
      }
    }
  }
}
