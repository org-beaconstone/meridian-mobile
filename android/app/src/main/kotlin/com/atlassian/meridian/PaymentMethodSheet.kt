package com.atlassian.meridian

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.MaterialTheme
import androidx.compose.material.RadioButton
import androidx.compose.material.Text
import androidx.compose.material.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp

@Composable
fun PaymentMethodSelector(
  loading: Boolean,
  rails: List<PaymentRail>,
  selected: PaymentMethod,
  enabled: Boolean,
  onOpen: () -> Unit,
) {
  val selectedRail = rails.firstOrNull { it.method == selected }
  Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
    Text("Payment method", style = MaterialTheme.typography.subtitle2)
    if (loading) {
      MethodSkeletonGroup()
    } else if (rails.isEmpty()) {
      Text("No payment methods are available.")
    } else {
      Column(
        Modifier
          .fillMaxWidth()
          .clip(RoundedCornerShape(12.dp))
          .background(Color.White)
          .clickable(enabled = enabled, onClick = onOpen)
          .padding(16.dp)
          .semantics(mergeDescendants = true) {
            contentDescription = when {
              selectedRail == null -> "Choose payment method"
              selectedRail.warning != null -> "Payment method, ${selectedRail.title}. ${selectedRail.warning}"
              else -> "Payment method, ${selectedRail.title}. ${selectedRail.badge}"
            }
          },
      ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
          Text(
            selectedRail?.title ?: "Choose payment method",
            style = MaterialTheme.typography.subtitle1,
          )
          Spacer(Modifier.weight(1f))
          Text("▲", color = Color(0xFF5C6B64))
        }
        selectedRail?.let { rail ->
          Text(rail.badge, style = MaterialTheme.typography.caption, color = Color(0xFF54635C))
          rail.warning?.let { warning ->
            Text(warning, style = MaterialTheme.typography.caption, color = Color(0xFF8D2517))
          }
        }
      }
    }
  }
}

@Composable
fun PaymentMethodBottomSheet(
  visible: Boolean,
  loading: Boolean,
  rails: List<PaymentRail>,
  selected: PaymentMethod,
  onSelect: (PaymentRail) -> Unit,
  onDismiss: () -> Unit,
) {
  if (!visible) return
  SheetOverlay(loading = loading, rails = rails, selected = selected, onSelect = onSelect, onDismiss = onDismiss)
}

@Composable
private fun SheetOverlay(
  loading: Boolean,
  rails: List<PaymentRail>,
  selected: PaymentMethod,
  onSelect: (PaymentRail) -> Unit,
  onDismiss: () -> Unit,
) {
  val consume = remember { MutableInteractionSource() }
  Box(Modifier.fillMaxSize()) {
    Box(
      Modifier
        .fillMaxSize()
        .background(Color(0xFF142C35).copy(alpha = 0.45f))
        .clickable(onClick = onDismiss)
        .clearAndSetSemantics {},
    )
    AnimatedVisibility(
      visible = true,
      enter = slideInVertically(animationSpec = tween(220)) { it },
      modifier = Modifier.align(Alignment.BottomCenter),
    ) {
      Column(
        Modifier
          .fillMaxWidth()
          .clip(RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp))
          .background(Color(0xFFF8F9F6))
          .clickable(interactionSource = consume, indication = null, onClick = {})
          .navigationBarsPadding()
          .verticalScroll(rememberScrollState())
          .padding(horizontal = 20.dp, vertical = 12.dp)
          .semantics { contentDescription = "Payment method" },
        verticalArrangement = Arrangement.spacedBy(12.dp),
      ) {
        Box(
          Modifier
            .align(Alignment.CenterHorizontally)
            .width(36.dp)
            .height(4.dp)
            .clip(RoundedCornerShape(2.dp))
            .background(Color(0xFF8B9588))
            .clearAndSetSemantics {},
        )
        Text(
          "Payment method",
          style = MaterialTheme.typography.h6,
          modifier = Modifier.semantics { heading() },
        )
        Text(
          "Simulated GBP rehearsal. No real payment is sent.",
          style = MaterialTheme.typography.caption,
          color = Color(0xFF57675E),
        )
        if (loading) {
          MethodSkeletonGroup()
        } else if (rails.isEmpty()) {
          Text("No payment methods are available.")
        } else {
          rails.forEach { rail ->
            PaymentRailRow(rail = rail, selected = rail.method == selected, onSelect = onSelect)
          }
        }
        TextButton(
          onClick = onDismiss,
          modifier = Modifier
            .align(Alignment.CenterHorizontally)
            .semantics { contentDescription = "Close payment methods" },
        ) {
          Text("Done")
        }
      }
    }
  }
}

@Composable
private fun PaymentRailRow(
  rail: PaymentRail,
  selected: Boolean,
  onSelect: (PaymentRail) -> Unit,
) {
  Row(
    Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(12.dp))
      .background(if (selected) Color(0xFFEDF4FF) else Color.White)
      .clickable { if (rail.selectable) onSelect(rail) }
      .padding(14.dp)
      .semantics {
        contentDescription = rail.announcement
        role = Role.RadioButton
        this.selected = selected
        stateDescription = rail.warning ?: rail.badge
      },
    verticalAlignment = Alignment.Top,
  ) {
    RadioButton(
      selected = selected,
      onClick = null,
      modifier = Modifier.clearAndSetSemantics {},
    )
    Column(Modifier.padding(start = 8.dp)) {
      Text(rail.title, style = MaterialTheme.typography.subtitle1)
      Text(rail.badge, style = MaterialTheme.typography.caption, color = Color(0xFF54635C))
      rail.warning?.let { warning ->
        Text(warning, style = MaterialTheme.typography.caption, color = Color(0xFF8D2517))
      }
    }
  }
}

@Composable
private fun MethodSkeletonGroup() {
  val transition = rememberInfiniteTransition()
  val alpha by transition.animateFloat(
    initialValue = 0.4f,
    targetValue = 1f,
    animationSpec = infiniteRepeatable(
      animation = tween(durationMillis = 900),
      repeatMode = RepeatMode.Reverse,
    ),
  )
  Column(
    verticalArrangement = Arrangement.spacedBy(10.dp),
    modifier = Modifier.semantics(mergeDescendants = true) {
      contentDescription = "Loading payment methods"
    },
  ) {
    repeat(2) {
      Box(
        Modifier
          .fillMaxWidth()
          .height(72.dp)
          .clip(RoundedCornerShape(12.dp))
          .background(Color(0xFFD5DDD0).copy(alpha = alpha)),
      )
    }
  }
}
