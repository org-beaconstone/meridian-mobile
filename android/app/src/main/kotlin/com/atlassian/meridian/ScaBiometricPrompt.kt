package com.atlassian.meridian

import android.os.Handler
import android.os.Looper
import androidx.biometric.BiometricPrompt
import androidx.fragment.app.FragmentActivity
import java.util.concurrent.Executor
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Android BiometricPrompt for a European payment. Device credential is not accepted here;
 * a failed or unavailable prompt returns to the in-app passcode with the payment draft intact.
 */
class ScaBiometricPrompt(private val activity: FragmentActivity) {
  suspend fun authenticate(promptCopy: String): BiometricStatus = suspendCancellableCoroutine { cont ->
    fun finish(status: BiometricStatus) {
      Handler(Looper.getMainLooper()).post {
        if (cont.isActive) cont.resume(status)
      }
    }

    val executor = Executor { command -> activity.runOnUiThread(command) }
    val prompt = BiometricPrompt(
      activity,
      executor,
      object : BiometricPrompt.AuthenticationCallback() {
        override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
          finish(BiometricStatus.SUCCESS)
        }

        override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
          val status = when (errorCode) {
            BiometricPrompt.ERROR_NO_BIOMETRICS,
            BiometricPrompt.ERROR_HW_NOT_PRESENT,
            BiometricPrompt.ERROR_HW_UNAVAILABLE,
            BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL,
            -> BiometricStatus.UNAVAILABLE
            BiometricPrompt.ERROR_USER_CANCELED,
            BiometricPrompt.ERROR_CANCELED,
            BiometricPrompt.ERROR_NEGATIVE_BUTTON,
            -> BiometricStatus.CANCELLED
            else -> BiometricStatus.FAILED
          }
          finish(status)
        }
      },
    )
    val info = BiometricPrompt.PromptInfo.Builder()
      .setTitle(promptCopy)
      .setSubtitle(promptCopy)
      .setNegativeButtonText("Use passcode")
      .build()
    prompt.authenticate(info)
    cont.invokeOnCancellation { prompt.cancelAuthentication() }
  }
}
