package com.atlassian.meridian

import android.os.Build
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

/**
 * Native Android challenge UI. Uses BiometricPrompt when the device can authenticate.
 * Otherwise the caller shows a native confirmation with the same sentence.
 * Device biometric builds were not executed in this environment.
 */
class BiometricScaHandler(
  private val activity: FragmentActivity,
) : ScaChallengeHandler {
  var fallback: (suspend (String) -> Boolean)? = null

  override suspend fun confirmEuropeanPayment(prompt: String): Boolean {
    val reason = prompt.ifBlank { Sca.EUROPEAN_PAYMENT }
    val system = runCatching { authenticate(reason) }.getOrNull()
    if (system != null) return system
    return fallback?.invoke(reason) ?: false
  }

  private suspend fun authenticate(reason: String): Boolean? = withContext(Dispatchers.Main) {
    val authenticators = BiometricManager.Authenticators.BIOMETRIC_WEAK
    val can = BiometricManager.from(activity).canAuthenticate(authenticators)
    if (can != BiometricManager.BIOMETRIC_SUCCESS) return@withContext null
    suspendCancellableCoroutine { continuation ->
      val executor = if (Build.VERSION.SDK_INT >= 28) {
        activity.mainExecutor
      } else {
        java.util.concurrent.Executor { command -> activity.runOnUiThread(command) }
      }
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
      continuation.invokeOnCancellation { prompt.cancelAuthentication() }
      prompt.authenticate(
        BiometricPrompt.PromptInfo.Builder()
          .setTitle(reason)
          .setDescription(reason)
          .setNegativeButtonText("Cancel")
          .setAllowedAuthenticators(authenticators)
          .build(),
      )
    }
  }
}
