package com.atlassian.meridian

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.LocalIndication
import androidx.compose.material.MaterialTheme
import androidx.compose.material.RadioButton
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import android.provider.Settings

private val Ink = Color(PaymentTextColors.ink.argb)
private val Surface = Color(PaymentTextColors.surface.argb)
private val Secondary = Color(PaymentTextColors.secondary.argb)
private val Action = Color(PaymentTextColors.action.argb)
private val SelectedFill = Color(PaymentTextColors.selectedFill.argb)
private val Border = Color(PaymentTextColors.border.argb)
private val ShimmerBase = Color(PaymentTextColors.shimmer.argb)
private val CardShape = RoundedCornerShape(12.dp)

@Composable
fun PaymentCorridorSelection(
  selected: PaymentCorridor,
  enabled: Boolean,
  onSelect: (PaymentCorridor) -> Unit,
  modifier: Modifier = Modifier,
) {
  Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
    Text(
      "Payment corridor",
      color = Ink,
      fontWeight = FontWeight.SemiBold,
      style = MaterialTheme.typography.subtitle1,
      modifier = Modifier.semantics { heading() },
    )
    PaymentCorridor.values().forEach { corridor ->
      val isSelected = corridor == selected
      SelectableCard(
        selected = isSelected,
        enabled = enabled,
        label = corridorAccessibilityLabel(corridor),
        onClick = { onSelect(corridor) },
      ) {
        Text(corridor.title, color = Ink, style = MaterialTheme.typography.body1)
        Text(corridor.summary, color = Secondary, style = MaterialTheme.typography.body2)
      }
    }
  }
}

@Composable
fun PaymentMethodSelection(
  phase: PaymentMethodPhase,
  selected: PaymentMethod?,
  enabled: Boolean,
  onSelect: (PaymentMethod) -> Unit,
  modifier: Modifier = Modifier,
) {
  Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
    Text(
      "Payment method",
      color = Ink,
      fontWeight = FontWeight.SemiBold,
      style = MaterialTheme.typography.subtitle1,
      modifier = Modifier.semantics { heading() },
    )
    when (phase) {
      PaymentMethodPhase.Loading -> PaymentMethodShimmer()
      is PaymentMethodPhase.Unavailable -> PaymentMethodNotice("Payment methods unavailable", phase.message)
      is PaymentMethodPhase.Empty -> PaymentMethodNotice("No payment methods", emptyPaymentMethodsMessage(phase.corridor))
      is PaymentMethodPhase.Ready -> PaymentOptionList(phase.options, selected, enabled, onSelect)
    }
  }
}

@Composable
private fun PaymentOptionList(
  options: List<PaymentOption>,
  selected: PaymentMethod?,
  enabled: Boolean,
  onSelect: (PaymentMethod) -> Unit,
) {
  BoxWithConstraints(Modifier.fillMaxWidth()) {
    val fontScale = LocalDensity.current.fontScale
    val sideBySide = options.size > 1 && usesSideBySideRails(maxWidth.value.toDouble(), fontScale.toDouble())
    if (sideBySide) {
      Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
        options.forEach { option ->
          Box(Modifier.weight(1f)) {
            PaymentOptionCard(option, selected == option.method, enabled, onSelect)
          }
        }
      }
    } else {
      Column(verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
        options.forEach { option ->
          PaymentOptionCard(option, selected == option.method, enabled, onSelect)
        }
      }
    }
  }
}

@Composable
private fun PaymentOptionCard(
  option: PaymentOption,
  selected: Boolean,
  enabled: Boolean,
  onSelect: (PaymentMethod) -> Unit,
) {
  SelectableCard(
    selected = selected,
    enabled = enabled,
    label = option.accessibilityLabel,
    onClick = { onSelect(option.method) },
  ) {
    Text(option.railLabel, color = Ink, style = MaterialTheme.typography.body1)
    Text(
      "British pounds · GBP",
      color = Secondary,
      style = MaterialTheme.typography.body2,
      modifier = Modifier.clearAndSetSemantics {},
    )
    if (selected) {
      Text(
        "Selected",
        color = Ink,
        fontWeight = FontWeight.SemiBold,
        style = MaterialTheme.typography.body2,
        modifier = Modifier.clearAndSetSemantics {},
      )
    }
  }
}

@Composable
private fun SelectableCard(
  selected: Boolean,
  enabled: Boolean,
  label: String,
  onClick: () -> Unit,
  content: @Composable () -> Unit,
) {
  val isSelected = selected
  val interaction = remember { MutableInteractionSource() }
  val focused by interaction.collectIsFocusedAsState()
  val borderColor = when {
    focused -> Action
    isSelected -> Ink
    else -> Border
  }
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .heightIn(min = 48.dp)
      .clip(CardShape)
      .background(if (isSelected) SelectedFill else Surface)
      .border(width = if (focused) 3.dp else 1.dp, color = borderColor, shape = CardShape)
      .semantics(mergeDescendants = true) {
        role = Role.RadioButton
        this.selected = isSelected
        contentDescription = label + if (isSelected) ". Selected" else ". Not selected"
      }
      .selectable(
        selected = isSelected,
        interactionSource = interaction,
        indication = LocalIndication.current,
        enabled = enabled,
        role = Role.RadioButton,
        onClick = onClick,
      )
      .padding(16.dp),
    verticalAlignment = Alignment.Top,
  ) {
    RadioButton(
      selected = isSelected,
      onClick = null,
      enabled = enabled,
      modifier = Modifier.clearAndSetSemantics {},
    )
    Spacer(Modifier.width(12.dp))
    Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.weight(1f)) {
      content()
    }
  }
}

@Composable
private fun PaymentMethodShimmer() {
  Column(
    verticalArrangement = Arrangement.spacedBy(12.dp),
    modifier = Modifier
      .fillMaxWidth()
      .clearAndSetSemantics { contentDescription = paymentMethodsLoadingLabel },
  ) {
    ShimmerCard()
    ShimmerCard()
  }
}

@Composable
private fun ShimmerCard() {
  val reduceMotion = animationScale() == 0f
  val transition = rememberInfiniteTransition()
  val animated by transition.animateFloat(
    initialValue = 0f,
    targetValue = 1f,
    animationSpec = infiniteRepeatable(
      animation = tween(durationMillis = 1150, easing = LinearEasing),
      repeatMode = RepeatMode.Restart,
    ),
  )
  val shift = if (reduceMotion) 0f else animated
  Row(
    Modifier
      .fillMaxWidth()
      .clip(CardShape)
      .background(Surface)
      .border(1.dp, Border.copy(alpha = 0.45f), CardShape)
      .padding(16.dp),
    verticalAlignment = Alignment.Top,
  ) {
    Box(
      Modifier
        .size(22.dp)
        .clip(CircleShape)
        .background(ShimmerBase),
    )
    Spacer(Modifier.width(12.dp))
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
      ShimmerBar(shift, 0.72f)
      ShimmerBar(shift, 0.42f)
    }
  }
}

@Composable
private fun ShimmerBar(shift: Float, fraction: Float) {
  BoxWithConstraints(Modifier.fillMaxWidth(fraction).height(14.dp)) {
    val widthPx = constraints.maxWidth.toFloat()
    Box(
      Modifier
        .fillMaxWidth()
        .height(14.dp)
        .clip(RoundedCornerShape(6.dp))
        .background(
          Brush.horizontalGradient(
            colors = listOf(ShimmerBase, Color.White, ShimmerBase),
            startX = (shift * widthPx * 2f) - widthPx,
            endX = shift * widthPx * 2f,
          ),
        ),
    )
  }
}

@Composable
private fun PaymentMethodNotice(title: String, message: String) {
  Column(
    Modifier
      .fillMaxWidth()
      .clip(CardShape)
      .background(Surface)
      .border(1.dp, Border, CardShape)
      .padding(16.dp)
      .clearAndSetSemantics { contentDescription = "$title. $message" },
    verticalArrangement = Arrangement.spacedBy(6.dp),
  ) {
    Text(
      title,
      color = Ink,
      fontWeight = FontWeight.SemiBold,
      style = MaterialTheme.typography.body1,
    )
    Text(message, color = Secondary, style = MaterialTheme.typography.body2)
  }
}

@Composable
private fun animationScale(): Float {
  val context = LocalContext.current
  return Settings.Global.getFloat(
    context.contentResolver,
    Settings.Global.ANIMATOR_DURATION_SCALE,
    1f,
  )
}
