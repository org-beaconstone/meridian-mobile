package com.atlassian.meridian

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

/**
 * Opens an allowlisted bank HTTPS URL. App-link returns are handled by [MainActivity].
 */
fun openAllowlistedBank(activity: FragmentActivity, url: String): Boolean {
  if (!BankAllowlist.permitsHandoff(url)) return false
  return try {
    activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addCategory(Intent.CATEGORY_BROWSABLE))
    true
  } catch (_: ActivityNotFoundException) {
    false
  }
}

/**
 * Invokes the platform biometric prompt for an in-app SCA challenge.
 * A missing sensor or a cancel resolves false so the customer can use the rehearsal PIN.
 */
fun confirmDeviceBiometric(activity: FragmentActivity, onResult: (Boolean) -> Unit) {
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
  val info = BiometricPrompt.PromptInfo.Builder()
    .setTitle("Confirm payment")
    .setSubtitle("Strong customer authentication")
    .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
    .setNegativeButtonText("Use PIN")
    .build()
  try {
    prompt.authenticate(info)
  } catch (_: Exception) {
    onResult(false)
  }
}
