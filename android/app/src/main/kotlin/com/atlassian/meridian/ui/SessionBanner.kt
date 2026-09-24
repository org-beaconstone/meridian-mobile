package com.atlassian.meridian.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.ButtonDefaults
import androidx.compose.material.Text
import androidx.compose.material.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.atlassian.meridian.SessionBannerPresentation
import com.atlassian.meridian.SessionBannerTokens

/**
 * Dismissible session banner for the payment screen.
 *
 * The banner is presentation only. It sits above the payment method picker,
 * does not disable payment actions, and announces state changes through
 * [LiveRegionMode.Polite].
 */
@Composable
fun PaymentSessionBanner(
  presentation: SessionBannerPresentation,
  onDismiss: () -> Unit,
  modifier: Modifier = Modifier,
) {
  if (presentation is SessionBannerPresentation.Hidden) return

  val dark = isSystemInDarkTheme()
  when (presentation) {
    SessionBannerPresentation.Hidden -> Unit
    SessionBannerPresentation.Skeleton -> SkeletonBar(dark)
    is SessionBannerPresentation.Visible -> VisibleBanner(
      presentation = presentation,
      dark = dark,
      onDismiss = onDismiss,
      modifier = modifier,
    )
  }
}

/**
 * Polite live region kept beside the status line so session changes and
 * dismissal are announced without adding a gap in the payment column.
 */
@Composable
fun SessionBannerAnnouncer(announcement: String) {
  if (announcement.isEmpty()) return
  Text(
    text = announcement,
    modifier = Modifier
      .semantics { liveRegion = LiveRegionMode.Polite }
      .height(0.dp)
      .alpha(0f),
    color = Color.Transparent,
    fontSize = 1.sp,
    maxLines = 1,
  )
}

@Composable
private fun SkeletonBar(dark: Boolean) {
  val color = Color((if (dark) SessionBannerTokens.SKELETON_DARK else SessionBannerTokens.SKELETON_LIGHT) or 0xFF000000)
  Box(
    Modifier
      .fillMaxWidth()
      .height(44.dp)
      .clip(RoundedCornerShape(10.dp))
      .background(color),
  )
}

@Composable
private fun VisibleBanner(
  presentation: SessionBannerPresentation.Visible,
  dark: Boolean,
  onDismiss: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val palette = SessionBannerTokens.forTone(presentation.tone).let { (light, night) -> if (dark) night else light }
  val background = Color(palette.background or 0xFF000000)
  val text = Color(palette.text or 0xFF000000)
  Row(
    modifier = modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(10.dp))
      .background(background)
      .padding(start = 16.dp, end = 4.dp, top = 4.dp, bottom = 4.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(8.dp),
  ) {
    BannerLine(
      core = presentation.coreMessage,
      detail = presentation.detail,
      color = text,
      modifier = Modifier.weight(1f),
    )
    if (presentation.dismissible) {
      TextButton(
        onClick = onDismiss,
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp),
        modifier = Modifier.heightIn(min = 48.dp),
        colors = ButtonDefaults.textButtonColors(contentColor = text),
      ) {
        Text(
          "Dismiss",
          maxLines = 1,
          fontWeight = FontWeight.SemiBold,
          modifier = Modifier.semantics { contentDescription = "Dismiss session banner" },
        )
      }
    }
  }
}

/**
 * One line. The detail slot (corridor or device) receives the remaining width
 * and ellipsizes before the core state message does.
 */
@Composable
private fun BannerLine(core: String, detail: String?, color: Color, modifier: Modifier = Modifier) {
  val style = TextStyle(color = color, fontSize = 14.sp, fontWeight = FontWeight.Medium)
  BoxWithConstraints(modifier) {
    val measurer = rememberTextMeasurer()
    val available = constraints.maxWidth
    val coreWidth = measurer.measure(
      text = core,
      style = style,
      maxLines = 1,
      softWrap = false,
      overflow = TextOverflow.Clip,
      constraints = Constraints(maxWidth = available),
    ).getLineRight(0).toInt()
    val showDetail = !detail.isNullOrBlank() && coreWidth < available
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
      Text(
        text = core,
        style = style,
        maxLines = 1,
        softWrap = false,
        overflow = TextOverflow.Ellipsis,
        modifier = if (showDetail) {
          Modifier.width(with(LocalDensity.current) { coreWidth.toDp() })
        } else {
          Modifier.weight(1f)
        },
      )
      if (showDetail) {
        Text(
          text = " $detail",
          style = style,
          maxLines = 1,
          softWrap = false,
          overflow = TextOverflow.Ellipsis,
          modifier = Modifier.weight(1f),
        )
      }
    }
  }
}
