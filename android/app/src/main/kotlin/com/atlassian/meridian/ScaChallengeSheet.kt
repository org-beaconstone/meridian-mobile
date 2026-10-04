package com.atlassian.meridian

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.Button
import androidx.compose.material.MaterialTheme
import androidx.compose.material.Surface
import androidx.compose.material.Text
import androidx.compose.material.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.delay

@Composable
fun ScaChallengeSheet(
  binding: ScaPaymentBinding,
  activity: FragmentActivity,
  onCancel: () -> Unit,
  onVerified: (ScaVerification) -> Unit,
) {
  val engine = remember(binding.idempotencyKey) { ScaChallengeEngine(binding) }
  var snap by remember(binding.idempotencyKey) {
    mutableStateOf(engine.snapshot(System.currentTimeMillis() / 1000))
  }
  LaunchedEffect(binding.idempotencyKey) {
    if (biometricAuthenticators(activity) == null) {
      snap = engine.markBiometricsUnavailable(System.currentTimeMillis() / 1000)
    }
  }
  LaunchedEffect(snap.secondsLocked) {
    if (snap.secondsLocked > 0) {
      delay(1000)
      snap = engine.snapshot(System.currentTimeMillis() / 1000)
    }
  }
  fun apply(next: ScaSnapshot) {
    snap = next
    val verification = next.verification
    if (verification != null) onVerified(verification)
  }
  Dialog(onDismissRequest = onCancel) {
    Surface(shape = RoundedCornerShape(16.dp), modifier = Modifier.width(360.dp)) {
      Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
          if (snap.phase == ScaPhase.Biometric) "Confirm it's you" else "Security passcode",
          style = MaterialTheme.typography.h6,
          modifier = Modifier.testTag("sca-title"),
        )
        Text(
          "Possession plus a second factor stay inside Meridian. This check does not open a browser or a payment provider.",
          style = MaterialTheme.typography.caption,
        )
        if (snap.phase == ScaPhase.Biometric) {
          Button(
            onClick = {
              launchInAppBiometric(activity) { outcome ->
                if (outcome == null) return@launchInAppBiometric
                val now = System.currentTimeMillis() / 1000
                apply(
                  when (outcome) {
                    BiometricOutcome.succeeded -> engine.succeedBiometrics(now)
                    BiometricOutcome.rejected -> engine.rejectBiometrics(now)
                    BiometricOutcome.bypassed -> engine.bypassBiometrics(now)
                    BiometricOutcome.unavailable -> engine.markBiometricsUnavailable(now)
                  },
                )
              }
            },
            modifier = Modifier.fillMaxWidth(),
          ) { Text("Verify with biometrics") }
          TextButton(
            onClick = { apply(engine.bypassBiometrics(System.currentTimeMillis() / 1000)) },
            modifier = Modifier.fillMaxWidth(),
          ) { Text("Use passcode instead") }
        } else {
          snap.rejectionBanner?.let { banner ->
            Text(
              banner,
              color = Color(0xFF8D2517),
              modifier = Modifier.testTag("sca-banner"),
            )
          }
          if (snap.biometric == BiometricOutcome.unavailable && snap.rejectionBanner == null) {
            Text(ScaChallenge.BIOMETRICS_UNAVAILABLE_NOTE, style = MaterialTheme.typography.caption)
          }
          Text(
            snap.maskedPasscode,
            style = MaterialTheme.typography.h5,
            modifier = Modifier
              .testTag("sca-dots")
              .semantics { contentDescription = "${snap.enteredCount} of 6 digits entered" },
          )
          if (snap.secondsLocked > 0) {
            Text("Try again in ${snap.secondsLocked}s", color = Color(0xFF8D2517))
          } else {
            snap.passcodeMessage?.let { Text(it, color = Color(0xFF8D2517)) }
          }
          PasscodeKeypad(
            enabled = snap.secondsLocked == 0L && snap.phase == ScaPhase.Passcode,
            onDigit = { apply(engine.appendDigit(it, System.currentTimeMillis() / 1000)) },
            onDelete = { apply(engine.deleteDigit(System.currentTimeMillis() / 1000)) },
          )
          Text(
            "Fictional rehearsal passcode: ${ScaChallenge.REHEARSAL_PIN}. It stays on this device and is not sent to the API.",
            style = MaterialTheme.typography.caption,
          )
        }
        TextButton(onClick = onCancel, modifier = Modifier.fillMaxWidth()) { Text("Cancel") }
      }
    }
  }
}

@Composable
private fun PasscodeKeypad(
  enabled: Boolean,
  onDigit: (Int) -> Unit,
  onDelete: () -> Unit,
) {
  val rows = listOf(listOf(1, 2, 3), listOf(4, 5, 6), listOf(7, 8, 9))
  Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
    rows.forEach { row ->
      Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        row.forEach { digit ->
          Button(
            onClick = { onDigit(digit) },
            enabled = enabled,
            modifier = Modifier.weight(1f),
          ) { Text(digit.toString()) }
        }
      }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
      Spacer(Modifier.weight(1f))
      Button(onClick = { onDigit(0) }, enabled = enabled, modifier = Modifier.weight(1f)) { Text("0") }
      Button(onClick = onDelete, enabled = enabled, modifier = Modifier.weight(1f)) { Text("Delete") }
    }
  }
}
