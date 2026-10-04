package com.atlassian.meridian

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.Button
import androidx.compose.material.MaterialTheme
import androidx.compose.material.OutlinedTextField
import androidx.compose.material.Text
import androidx.compose.material.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/**
 * Amount field with an en_GB £ prefix. TalkBack reads [AmountEvaluation.spoken]
 * ("10 pounds and 50 pence"). The field and helper use wrap content with no max
 * height, so a 200% font scale grows the control instead of clipping it.
 */
@Composable
fun AmountInputField(
  text: String,
  onTextChange: (String) -> Unit,
  enabled: Boolean,
) {
  val evaluation = evaluateAmount(text)
  val showError = text.isNotBlank() && !evaluation.isValid
  Column(Modifier.fillMaxWidth()) {
    Text("Amount (GBP)", style = MaterialTheme.typography.subtitle1)
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
      Text(
        evaluation.prefix,
        style = MaterialTheme.typography.h6,
        modifier = Modifier.padding(end = 8.dp).clearAndSetSemantics { },
      )
      OutlinedTextField(
        value = text,
        onValueChange = onTextChange,
        enabled = enabled,
        modifier = Modifier
          .weight(1f)
          .semantics {
            contentDescription = evaluation.spoken
            stateDescription = evaluation.spoken
          },
        placeholder = { Text("0.00") },
        textStyle = MaterialTheme.typography.body1,
        singleLine = false,
        maxLines = 3,
        isError = showError,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
      )
    }
    Text(
      evaluation.helper,
      style = MaterialTheme.typography.body2,
      color = if (showError) MaterialTheme.colors.error else MaterialTheme.colors.onSurface.copy(alpha = 0.6f),
      modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
    )
  }
}

/** European IBAN field. Helper text updates on each change with format and checksum errors. */
@Composable
fun IbanInputField(
  text: String,
  onTextChange: (String) -> Unit,
  enabled: Boolean,
) {
  val check = validateIban(text)
  val showError = text.isNotBlank() && !check.isValid
  Column(Modifier.fillMaxWidth()) {
    Text("Recipient IBAN", style = MaterialTheme.typography.subtitle1)
    OutlinedTextField(
      value = text,
      onValueChange = onTextChange,
      enabled = enabled,
      modifier = Modifier
        .fillMaxWidth()
        .semantics {
          contentDescription = "Recipient IBAN"
          stateDescription = check.helper
        },
      placeholder = { Text("DE89 3704 0044 0532 0130 00") },
      textStyle = MaterialTheme.typography.body1,
      singleLine = false,
      maxLines = 4,
      isError = showError,
    )
    Text(
      check.helper,
      style = MaterialTheme.typography.body2,
      color = if (showError) MaterialTheme.colors.error else MaterialTheme.colors.onSurface.copy(alpha = 0.6f),
      modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
    )
  }
}

@Composable
fun GrowingButton(
  title: String,
  enabled: Boolean,
  onClick: () -> Unit,
) {
  Button(
    onClick = onClick,
    enabled = enabled,
    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
  ) {
    Text(
      title,
      modifier = Modifier.weight(1f),
      textAlign = TextAlign.Center,
      softWrap = true,
      overflow = TextOverflow.Visible,
    )
  }
}

@Composable
fun GrowingTextButton(
  title: String,
  enabled: Boolean,
  onClick: () -> Unit,
) {
  TextButton(
    onClick = onClick,
    enabled = enabled,
    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
  ) {
    Text(
      title,
      modifier = Modifier.weight(1f),
      textAlign = TextAlign.Center,
      softWrap = true,
      overflow = TextOverflow.Visible,
    )
  }
}
