package com.atlassian.meridian

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * Presents Android BiometricPrompt. Hardware that is missing or not enrolled
 * returns false so the caller can keep the payment and ask for the in-app passcode.
 * The biometric sample is not sent to the API or a payment provider.
 */
object ScaBiometrics {
  suspend fun authenticate(activity: FragmentActivity): Boolean {
    val manager = BiometricManager.from(activity)
    val can = manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK)
    if (can != BiometricManager.BIOMETRIC_SUCCESS) return false
    return suspendCancellableCoroutine { continuation ->
      val executor = ContextCompat.getMainExecutor(activity)
      val prompt = BiometricPrompt(
        activity,
        executor,
        object : BiometricPrompt.AuthenticationCallback() {
          override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
            if (continuation.isActive) continuation.resume(true)
          }

          override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
            if (continuation.isActive) continuation.resume(false)
          }
        },
      )
      val info = BiometricPrompt.PromptInfo.Builder()
        .setTitle(ScaStepUp.BIOMETRIC_PROMPT)
        .setNegativeButtonText("Use passcode")
        .build()
      continuation.invokeOnCancellation { prompt.cancelAuthentication() }
      prompt.authenticate(info)
    }
  }
}
