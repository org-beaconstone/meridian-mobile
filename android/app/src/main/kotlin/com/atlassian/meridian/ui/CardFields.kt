package com.atlassian.meridian.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.weight
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.OutlinedTextField
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp

/**
 * Net-new inline grouped fields layout: the expiry date and CVV placed two-up on a single row.
 *
 * meridian-mobile has no shared grouped-field pattern, so this is a from-scratch component. It is
 * layout-only over standard [OutlinedTextField]s; it does not implement card storage or submission
 * (consistent with the "no real payments/credentials" constraint) — the values are surfaced to the
 * caller via callbacks so this stays a pure presentation component.
 *
 * Accessibility: each field keeps its own label and its own accessible node, so TalkBack reads
 * "Expiry (MM/YY)" and "CVV" independently even though they share a row. Numeric keyboards are
 * requested for both.
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
  Row(
    modifier = modifier.fillMaxWidth(),
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    OutlinedTextField(
      value = expiry,
      onValueChange = { onExpiryChange(sanitizeExpiry(it)) },
      label = { Text("Expiry (MM/YY)") },
      placeholder = { Text("MM/YY") },
      singleLine = true,
      enabled = enabled,
      keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
      modifier = Modifier.weight(1f),
    )
    OutlinedTextField(
      value = cvv,
      onValueChange = { onCvvChange(it.filter(Char::isDigit).take(4)) },
      label = { Text("CVV") },
      placeholder = { Text("123") },
      singleLine = true,
      enabled = enabled,
      keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
      modifier = Modifier.weight(1f),
    )
  }
}

/**
 * Light input hygiene for the expiry field: keep only digits, cap at 4 (MMYY) and auto-insert the
 * slash after the month. This is presentation formatting only, not validation of a real card.
 */
internal fun sanitizeExpiry(raw: String): String {
  val digits = raw.filter(Char::isDigit).take(4)
  return when {
    digits.length <= 2 -> digits
    else -> digits.substring(0, 2) + "/" + digits.substring(2)
  }
}
