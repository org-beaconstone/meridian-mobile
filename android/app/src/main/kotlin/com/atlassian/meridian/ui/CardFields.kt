package com.atlassian.meridian.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.weight
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.OutlinedTextField
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Formatting + validation helpers for the grouped card fields. Kept pure so
 * they can be unit tested without a Compose runtime.
 */
object CardFieldFormat {
  /** Normalise raw expiry input into a partial or complete `MM/YY` string. */
  fun formatExpiry(raw: String): String {
    val digits = raw.filter { it.isDigit() }.take(4)
    return when {
      digits.isEmpty() -> ""
      digits.length <= 2 -> digits
      else -> "${digits.substring(0, 2)}/${digits.substring(2)}"
    }
  }

  /** Keep only digits, capped at [maxLength] (CVV is 3-4 digits). */
  fun formatCvv(raw: String, maxLength: Int = 4): String =
    raw.filter { it.isDigit() }.take(maxLength)

  /** A complete `MM/YY` with a month in 01..12. */
  fun isValidExpiry(value: String): Boolean {
    val match = Regex("^(\\d{2})/(\\d{2})$").matchEntire(value) ?: return false
    val month = match.groupValues[1].toIntOrNull() ?: return false
    return month in 1..12
  }

  fun isValidCvv(value: String): Boolean = value.length in 3..4 && value.all { it.isDigit() }
}

/**
 * Net-new inline grouped fields layout: the expiry date and CVV rendered as a
 * two-up row. This is a new form pattern for the app (there is no shared
 * design-system form component to retrofit).
 *
 * Input is normalised as the user types (expiry -> `MM/YY`, CVV -> digits) and
 * each field carries its own accessibility label so TalkBack reads them
 * distinctly even though they share a row.
 */
@Composable
fun ExpiryCvvRow(
  expiry: String,
  onExpiryChange: (String) -> Unit,
  cvv: String,
  onCvvChange: (String) -> Unit,
  modifier: Modifier = Modifier,
  enabled: Boolean = true,
) {
  val dark = isSystemInDarkTheme()
  Row(
    modifier = modifier.fillMaxWidth(),
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    Column(Modifier.weight(1f)) {
      Text(
        text = "Expiry date",
        color = MeridianTokens.onSurfaceMuted.resolve(dark),
        fontSize = 12.sp,
        fontWeight = FontWeight.Medium,
        modifier = Modifier.padding(bottom = 4.dp),
      )
      OutlinedTextField(
        value = expiry,
        onValueChange = { onExpiryChange(CardFieldFormat.formatExpiry(it)) },
        placeholder = { Text("MM/YY") },
        singleLine = true,
        enabled = enabled,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        modifier = Modifier
          .fillMaxWidth()
          .semantics { contentDescription = "Card expiry date, month and year" },
      )
    }
    Column(Modifier.weight(1f)) {
      Text(
        text = "CVV",
        color = MeridianTokens.onSurfaceMuted.resolve(dark),
        fontSize = 12.sp,
        fontWeight = FontWeight.Medium,
        modifier = Modifier.padding(bottom = 4.dp),
      )
      OutlinedTextField(
        value = cvv,
        onValueChange = { onCvvChange(CardFieldFormat.formatCvv(it)) },
        placeholder = { Text("123") },
        singleLine = true,
        enabled = enabled,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
        modifier = Modifier
          .fillMaxWidth()
          .semantics { contentDescription = "Card security code, C V V" },
      )
    }
  }
}
