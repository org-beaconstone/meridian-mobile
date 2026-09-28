package com.atlassian.meridian

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.Button
import androidx.compose.material.ButtonDefaults
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

fun SessionColor.toComposeColor(): Color = Color(red, green, blue)

/**
 * Persistent session health for the payment and authentication screen.
 * The warning stays non-blocking. Only an expired session locks the transfer form.
 */
@Composable
fun SessionStatusBanner(
  presentation: SessionBannerPresentation,
  actionEnabled: Boolean = true,
  onExtend: () -> Unit,
  onReauthenticate: () -> Unit,
) {
  val background = presentation.background.toComposeColor()
  val foreground = presentation.foreground.toComposeColor()
  val tap = presentation.minimumTapTargetDp.dp

  val extendAction = presentation.extendActionLabel
  val reauthenticateAction = presentation.reauthenticateActionLabel
  if (extendAction != null) {
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .defaultMinSize(minWidth = tap, minHeight = tap)
        .background(background)
        .clickable(
          enabled = actionEnabled,
          role = Role.Button,
          onClickLabel = presentation.accessibilityHint,
          onClick = onExtend,
        )
        .semantics {
          contentDescription = presentation.accessibilityLabel
          liveRegion = LiveRegionMode.Polite
        }
        .padding(horizontal = 16.dp, vertical = 12.dp),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      BannerMessage(presentation.message, foreground)
    }
  } else if (reauthenticateAction != null) {
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .background(background)
        .semantics { liveRegion = LiveRegionMode.Assertive }
        .padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 12.dp),
    ) {
      Row(
        modifier = Modifier
          .defaultMinSize(minHeight = tap)
          .semantics { contentDescription = presentation.accessibilityLabel },
        verticalAlignment = Alignment.CenterVertically,
      ) {
        BannerMessage(presentation.message, foreground)
      }
      Spacer(Modifier.height(8.dp))
      Button(
        onClick = onReauthenticate,
        enabled = actionEnabled,
        modifier = Modifier
          .fillMaxWidth()
          .defaultMinSize(minWidth = tap, minHeight = tap)
          .semantics {
            contentDescription = "$reauthenticateAction. ${presentation.accessibilityHint}"
          },
        colors = ButtonDefaults.buttonColors(
          backgroundColor = Color.White,
          contentColor = foreground,
          disabledBackgroundColor = Color.White.copy(alpha = 0.7f),
          disabledContentColor = foreground.copy(alpha = 0.6f),
        ),
        elevation = ButtonDefaults.elevation(defaultElevation = 0.dp, pressedElevation = 0.dp),
        shape = RoundedCornerShape(8.dp),
      ) {
        Text(reauthenticateAction, fontSize = 16.sp)
      }
    }
  } else {
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .defaultMinSize(minWidth = tap, minHeight = tap)
        .background(background)
        .semantics {
          contentDescription = presentation.accessibilityLabel
          liveRegion = LiveRegionMode.Polite
        }
        .padding(horizontal = 16.dp, vertical = 12.dp),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      BannerMessage(presentation.message, foreground)
    }
  }
}

@Composable
private fun RowScope.BannerMessage(message: String, foreground: Color) {
  Spacer(
    Modifier
      .width(4.dp)
      .height(24.dp)
      .clip(RoundedCornerShape(2.dp))
      .background(foreground)
      .clearAndSetSemantics {},
  )
  Spacer(Modifier.width(12.dp))
  Text(
    message,
    color = foreground,
    fontSize = 16.sp,
    modifier = Modifier.weight(1f).clearAndSetSemantics {},
  )
}
