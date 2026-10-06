package com.atlassian.meridian

import android.os.Build
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

/**
 * Native biometric or device-PIN prompt for a rehearsal SCA step.
 * Cancellation leaves the payment unsent. The in-app PIN remains available.
 */
object ScaPrompt {
  fun authenticate(activity: FragmentActivity, onResult: (Boolean) -> Unit) {
    if (activity.isFinishing) {
      onResult(false)
      return
    }
    val executor = ContextCompat.getMainExecutor(activity)
    val prompt = BiometricPrompt(
      activity,
      executor,
      object : BiometricPrompt.AuthenticationCallback() {
        override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
          onResult(true)
        }

        override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
          onResult(false)
        }
      },
    )
    val builder = BiometricPrompt.PromptInfo.Builder()
      .setTitle("Confirm this payment")
      .setSubtitle("Strong Customer Authentication")
    if (Build.VERSION.SDK_INT >= 30) {
      val biometric = BiometricManager.Authenticators.BIOMETRIC_STRONG
      val deviceCredential = BiometricManager.Authenticators.DEVICE_CREDENTIAL
      val enrolled = BiometricManager.from(activity).canAuthenticate(biometric) == BiometricManager.BIOMETRIC_SUCCESS
      builder.setAllowedAuthenticators(if (enrolled) biometric or deviceCredential else deviceCredential)
    } else {
      builder
        .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_WEAK)
        .setNegativeButtonText("Use PIN")
    }
    try {
      prompt.authenticate(builder.build())
    } catch (_: Exception) {
      onResult(false)
    }
  }
}
