package com.atlassian.meridian

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.Text
import androidx.compose.material.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

fun SessionColor.toComposeColor(): Color = Color(red, green, blue)

/**
 * Persistent session banner for the payment and authentication screen.
 * Copy uses sp so TalkBack font scaling grows it. The action stays at least 48dp.
 */
@Composable
fun SessionStatusBanner(
  presentation: SessionBannerPresentation,
  refreshing: Boolean,
  onAction: () -> Unit,
) {
  val fontScale = LocalDensity.current.fontScale.toDouble()
  val tapTarget = SessionTextScale(fontScale).tapTargetPoints
  val shape = RoundedCornerShape(12.dp)
  Column(
    modifier = Modifier
      .fillMaxWidth()
      .clip(shape)
      .background(presentation.background.toComposeColor())
      .padding(16.dp)
      .testTag(SessionAccessibility.banner),
  ) {
    Row(verticalAlignment = Alignment.Top) {
      Box(
        modifier = Modifier
          .padding(top = 6.dp)
          .width(4.dp)
          .height(18.dp)
          .clip(RoundedCornerShape(2.dp))
          .background(presentation.foreground.toComposeColor()),
      )
      Column(
        modifier = Modifier
          .padding(start = 12.dp)
          .weight(1f),
      ) {
        Text(
          text = presentation.title,
          color = presentation.foreground.toComposeColor(),
          fontSize = 15.sp,
          fontWeight = FontWeight.SemiBold,
          modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
        )
        Text(
          text = presentation.message,
          color = presentation.foreground.toComposeColor(),
          fontSize = 13.sp,
          modifier = Modifier.padding(top = 4.dp),
        )
      }
    }
    val action = presentation.actionLabel
    val actionBackground = presentation.actionBackground
    val actionForeground = presentation.actionForeground
    if (action != null && actionBackground != null && actionForeground != null) {
      TextButton(
        onClick = onAction,
        enabled = !refreshing,
        modifier = Modifier
          .padding(top = 8.dp)
          .fillMaxWidth()
          .heightIn(min = tapTarget.dp)
          .clip(RoundedCornerShape(10.dp))
          .background(actionBackground.toComposeColor())
          .testTag(SessionAccessibility.action)
          .semantics {
            role = Role.Button
            contentDescription = if (refreshing) {
              "Refreshing session"
            } else {
              presentation.actionAccessibilityLabel ?: action
            }
          },
      ) {
        Text(
          text = if (refreshing) "Refreshing…" else action,
          color = actionForeground.toComposeColor(),
          fontSize = 15.sp,
        )
      }
    }
  }
}
