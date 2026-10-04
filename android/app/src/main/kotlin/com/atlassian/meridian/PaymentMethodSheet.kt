package com.atlassian.meridian

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.MaterialTheme
import androidx.compose.material.RadioButton
import androidx.compose.material.Text
import androidx.compose.material.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.invisibleToUser
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selectableGroup
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp

@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
@Composable
fun PaymentMethodSheet(
  model: PaymentMethodSheetModel,
  current: PaymentMethod,
  onSelect: (PaymentMethod) -> Unit,
  onClose: () -> Unit,
) {
  Column(
    Modifier
      .fillMaxWidth()
      .navigationBarsPadding()
      .padding(horizontal = 24.dp)
      .padding(bottom = 24.dp),
    verticalArrangement = Arrangement.spacedBy(8.dp),
  ) {
    Box(Modifier.fillMaxWidth().padding(top = 12.dp), contentAlignment = Alignment.Center) {
      Box(
        Modifier
          .size(width = 36.dp, height = 4.dp)
          .clip(RoundedCornerShape(2.dp))
          .background(Color(0xFFD5DDD4)),
      )
    }
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
      Column(Modifier.weight(1f)) {
        Text(
          "Payment method",
          style = MaterialTheme.typography.h6,
          modifier = Modifier.semantics { heading() },
        )
        Text("GBP · United Kingdom", style = MaterialTheme.typography.caption)
      }
      TextButton(onClick = onClose, modifier = Modifier.height(48.dp)) { Text("Done") }
    }
    if (model.loading) {
      Column(
        Modifier.semantics { contentDescription = "Loading payment methods" },
        verticalArrangement = Arrangement.spacedBy(8.dp),
      ) {
        repeat(model.placeholderCount) {
          Box(
            Modifier
              .fillMaxWidth()
              .height(48.dp)
              .clip(RoundedCornerShape(8.dp))
              .background(Color(0xFFE4E8E1)),
          )
        }
      }
    } else if (model.options.isEmpty()) {
      Text(
        "No payment method is available for this corridor.",
        modifier = Modifier.heightIn(min = 48.dp),
      )
    } else {
      Column(Modifier.selectableGroup(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        model.options.forEach { option ->
          val selected = current == option.method && option.selectable
          Row(
            Modifier
              .fillMaxWidth()
              .heightIn(min = 48.dp)
              .semantics(mergeDescendants = true) {
                role = Role.RadioButton
                contentDescription = option.accessibilityLabel
                stateDescription = option.helperText ?: ""
              }
              .clickable(enabled = option.selectable) { onSelect(option.method) },
            verticalAlignment = Alignment.CenterVertically,
          ) {
            RadioButton(
              selected = selected,
              onClick = { if (option.selectable) onSelect(option.method) },
              enabled = option.selectable,
              modifier = Modifier.size(48.dp).semantics { invisibleToUser() },
            )
            Column(Modifier.padding(start = 8.dp).weight(1f)) {
              Text(option.title, color = if (option.selectable) Color(0xFF142C35) else Color(0xFF6B756C))
              option.helperText?.let { Text(it, style = MaterialTheme.typography.caption) }
            }
          }
        }
      }
    }
  }
}
