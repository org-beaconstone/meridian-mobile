package com.atlassian.meridian

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private fun SessionColor.composeColor(): Color = Color(red / 255f, green / 255f, blue / 255f)

/**
 * Native session status banner for the payment and authentication screen.
 * Expiring and expired banners are the tap targets. Other states stay informational
 * so the warning does not block the transfer until the session has actually expired.
 */
@Composable
fun SessionStatusBanner(
  phase: SessionPhase,
  onExtend: () -> Unit,
  onReauthenticate: () -> Unit,
  actionEnabled: Boolean = true,
) {
  val tokens = sessionBannerTokens(phase)
  val copy = SessionBannerCopy.text(phase)
  val interactive = sessionOffersExtend(phase) || sessionBlocksInteraction(phase)
  val shape = RoundedCornerShape(12.dp)
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .sizeIn(
        minWidth = SessionTiming.minimumTapTargetDp.dp,
        minHeight = SessionTiming.minimumTapTargetDp.dp,
      )
      .clip(shape)
      .background(tokens.background.composeColor())
      .then(
        if (interactive) {
          Modifier.clickable(
            enabled = actionEnabled,
            onClickLabel = if (sessionOffersExtend(phase)) "Extend session" else "Re-authenticate",
            onClick = if (sessionOffersExtend(phase)) onExtend else onReauthenticate,
          )
        } else {
          Modifier
        },
      )
      .semantics {
        contentDescription = "Session status. $copy"
        liveRegion = if (sessionBlocksInteraction(phase)) LiveRegionMode.Assertive else LiveRegionMode.Polite
        if (interactive && !actionEnabled) stateDescription = "Session refresh in progress"
      }
      .padding(horizontal = 16.dp, vertical = 12.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    Box(
      modifier = Modifier
        .size(10.dp)
        .clip(CircleShape)
        .background(tokens.indicator.composeColor()),
    )
    Text(
      text = copy,
      color = tokens.foreground.composeColor(),
      fontSize = 15.sp,
      modifier = Modifier.clearAndSetSemantics {},
    )
  }
}
