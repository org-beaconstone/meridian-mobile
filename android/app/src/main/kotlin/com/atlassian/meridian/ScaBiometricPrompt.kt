package com.atlassian.meridian

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.fragment.app.FragmentActivity
import java.util.concurrent.Executor
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Android BiometricPrompt for the PSD2 step-up. Device credential is not accepted here;
 * failure or unavailability continues into the in-app passcode challenge.
 */
class AndroidBiometricAuthenticator(
  private val activity: FragmentActivity,
) : DeviceBiometric {
  override suspend fun authenticate(prompt: String): BiometricStatus {
    val authenticators = BiometricManager.Authenticators.BIOMETRIC_STRONG
    val can = try {
      BiometricManager.from(activity).canAuthenticate(authenticators)
    } catch (_: Exception) {
      return BiometricStatus.UNAVAILABLE
    }
    if (can != BiometricManager.BIOMETRIC_SUCCESS) return BiometricStatus.UNAVAILABLE

    return suspendCancellableCoroutine { cont ->
      val executor = Executor { command -> activity.runOnUiThread(command) }
      val callback = object : BiometricPrompt.AuthenticationCallback() {
        override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
          if (cont.isActive) cont.resume(BiometricStatus.SUCCESS)
        }

        override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
          if (!cont.isActive) return
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
          cont.resume(status)
        }
      }
      val promptUi = BiometricPrompt(activity, executor, callback)
      val info = BiometricPrompt.PromptInfo.Builder()
        .setTitle(prompt)
        .setAllowedAuthenticators(authenticators)
        .setNegativeButtonText("Use passcode")
        .build()
      cont.invokeOnCancellation { promptUi.cancelAuthentication() }
      promptUi.authenticate(info)
    }
  }
}
