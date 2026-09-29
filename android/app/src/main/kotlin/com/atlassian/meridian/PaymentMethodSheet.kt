package com.atlassian.meridian

import android.provider.Settings
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.RadioButton
import androidx.compose.material.RadioButtonDefaults
import androidx.compose.material.Text
import androidx.compose.material.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.dialog
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val Ink = Color(0xFF142C35)
private val SheetFill = Color(0xFFF8F9F6)
private val SelectedFill = Color(0xFFEDF4FF)
private val SelectedStroke = Color(0xFF1868DB)
private val IdleStroke = Color(0xFFDCE3D6)
private val WarningFill = Color(0xFFFFF6F4)
private val WarningStroke = Color(0xFFECC6BE)
private val WarningText = Color(0xFF8D2517)
private val SkeletonFill = Color(0xFFD5DDD4)

@Composable
fun PaymentMethodSheet(
  method: PaymentMethod,
  rails: List<PaymentMethodOption>?,
  onSelect: (PaymentMethod) -> Unit,
  onDismiss: () -> Unit,
) {
  val context = LocalContext.current
  val reduceMotion = remember {
    Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
  }
  var shown by remember { mutableStateOf(reduceMotion) }
  LaunchedEffect(reduceMotion) { shown = true }
  Box(Modifier.fillMaxSize()) {
    Box(
      Modifier
        .fillMaxSize()
        .background(Ink.copy(alpha = 0.46f))
        .clickable(
          interactionSource = remember { MutableInteractionSource() },
          indication = null,
          onClick = onDismiss,
        )
        .semantics { contentDescription = "Dismiss payment methods" },
    )
    AnimatedVisibility(
      visible = shown,
      modifier = Modifier.align(Alignment.BottomCenter),
      enter = if (reduceMotion) fadeIn(tween(0)) else slideInVertically { it } + fadeIn(),
    ) {
      Column(
        Modifier
          .fillMaxWidth()
          .clip(RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp))
          .background(SheetFill)
          .navigationBarsPadding()
          .padding(horizontal = 20.dp, vertical = 12.dp)
          .semantics {
            dialog()
            paneTitle = "Payment method"
          },
        verticalArrangement = Arrangement.spacedBy(12.dp),
      ) {
        Box(
          Modifier
            .align(Alignment.CenterHorizontally)
            .width(36.dp)
            .height(4.dp)
            .clip(RoundedCornerShape(2.dp))
            .background(Color(0xFFB7C0B6))
            .clearAndSetSemantics {},
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
          Text("Payment method", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Ink)
          Spacer(Modifier.weight(1f))
          TextButton(onClick = onDismiss) { Text("Close") }
        }
        if (rails == null) {
          Column(
            Modifier.semantics { contentDescription = "Loading payment methods" },
            verticalArrangement = Arrangement.spacedBy(10.dp),
          ) {
            SkeletonCard(reduceMotion)
            SkeletonCard(reduceMotion)
          }
        } else {
          Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            rails.forEachIndexed { index, option ->
              RailRow(
                option = option,
                chosen = option.method == method,
                position = index + 1,
                total = rails.size,
                onSelect = { onSelect(option.method) },
              )
            }
          }
        }
      }
    }
  }
}

@Composable
private fun SkeletonCard(reduceMotion: Boolean) {
  val transition = rememberInfiniteTransition()
  val animated by transition.animateFloat(
    initialValue = 0.35f,
    targetValue = 0.95f,
    animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
  )
  val alpha = if (reduceMotion) 0.7f else animated
  Box(
    Modifier
      .fillMaxWidth()
      .height(72.dp)
      .clip(RoundedCornerShape(12.dp))
      .background(SkeletonFill.copy(alpha = alpha))
      .clearAndSetSemantics {},
  )
}

@Composable
private fun RailRow(
  option: PaymentMethodOption,
  chosen: Boolean,
  position: Int,
  total: Int,
  onSelect: () -> Unit,
) {
  val spoken = buildString {
    append(option.accessibilityAnnouncement(position, total))
    if (chosen) append(", selected")
  }
  val fill = when {
    !option.available -> WarningFill
    chosen -> SelectedFill
    else -> Color.White
  }
  val stroke = when {
    !option.available -> WarningStroke
    chosen -> SelectedStroke
    else -> IdleStroke
  }
  Row(
    Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(12.dp))
      .background(fill)
      .border(1.dp, stroke, RoundedCornerShape(12.dp))
      .clickable(enabled = option.available, onClick = onSelect)
      .semantics(mergeDescendants = true) {
        contentDescription = spoken
        this.selected = chosen
        if (!option.available) disabled()
      }
      .padding(14.dp),
    verticalAlignment = Alignment.Top,
  ) {
    RadioButton(
      selected = chosen,
      onClick = null,
      enabled = option.available,
      colors = RadioButtonDefaults.colors(selectedColor = SelectedStroke),
      modifier = Modifier.clearAndSetSemantics {},
    )
    Column(Modifier.padding(start = 8.dp, top = 10.dp)) {
      Text(option.badge, color = if (option.available) Ink else Color(0xFF5C6758))
      option.warning?.let { warning ->
        Text(warning, color = WarningText, fontSize = 12.sp, modifier = Modifier.padding(top = 4.dp))
      }
    }
  }
}
