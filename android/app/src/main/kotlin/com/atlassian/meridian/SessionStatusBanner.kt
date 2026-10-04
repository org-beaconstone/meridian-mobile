package com.atlassian.meridian

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Persistent payment-session banner for the native payment and authentication screen.
 * TalkBack reads the status label from the live region. The control is not a modal.
 */
@Composable
fun SessionStatusBanner(
  state: SessionBannerState,
  remainingMillis: Long?,
  onRefresh: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val copy = sessionBannerCopy(
    state,
    if (state == SessionBannerState.EXPIRING_SOON) remainingMillis else null,
  )
  val palette = sessionBannerPalette(state)
  val background = sessionColor(palette.backgroundHex)
  val foreground = sessionColor(palette.foregroundHex)
  Row(
    modifier = modifier
      .fillMaxWidth()
      .defaultMinSize(minHeight = 48.dp)
      .background(background)
      .testTag("session-status-banner")
      .clickable(onClickLabel = "Refresh session", onClick = onRefresh)
      .semantics {
        liveRegion = LiveRegionMode.Polite
        contentDescription = copy.accessibilityLabel
      }
      .padding(horizontal = 16.dp, vertical = 10.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Box(
      Modifier
        .padding(end = 10.dp)
        .size(width = 4.dp, height = 28.dp)
        .background(foreground)
        .clearAndSetSemantics {},
    )
    SessionGlyph(copy.indicator, foreground)
    Text(
      copy.message,
      modifier = Modifier
        .padding(start = 10.dp)
        .clearAndSetSemantics {},
      color = foreground,
      fontWeight = FontWeight.SemiBold,
    )
  }
}

@Composable
private fun SessionGlyph(kind: String, color: Color) {
  Canvas(
    Modifier
      .padding(end = 0.dp)
      .size(18.dp)
      .clearAndSetSemantics {},
  ) {
    val stroke = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round)
    when (kind) {
      "check" -> {
        drawCircle(color = color, style = stroke)
        val path = Path().apply {
          moveTo(size.width * 0.28f, size.height * 0.52f)
          lineTo(size.width * 0.44f, size.height * 0.68f)
          lineTo(size.width * 0.74f, size.height * 0.36f)
        }
        drawPath(path, color, style = stroke)
      }
      "warning" -> {
        val path = Path().apply {
          moveTo(size.width / 2f, size.height * 0.08f)
          lineTo(size.width * 0.92f, size.height * 0.88f)
          lineTo(size.width * 0.08f, size.height * 0.88f)
          close()
        }
        drawPath(path, color, style = stroke)
        drawLine(
          color,
          start = Offset(size.width / 2f, size.height * 0.40f),
          end = Offset(size.width / 2f, size.height * 0.62f),
          strokeWidth = 2.dp.toPx(),
          cap = StrokeCap.Round,
        )
        drawCircle(
          color,
          radius = 1.5.dp.toPx(),
          center = Offset(size.width / 2f, size.height * 0.74f),
        )
      }
      "devices" -> {
        drawRoundRect(
          color = color,
          topLeft = Offset(size.width * 0.08f, size.height * 0.22f),
          size = Size(size.width * 0.46f, size.height * 0.62f),
          cornerRadius = CornerRadius(2.dp.toPx()),
          style = stroke,
        )
        drawRoundRect(
          color = color,
          topLeft = Offset(size.width * 0.38f, size.height * 0.08f),
          size = Size(size.width * 0.52f, size.height * 0.48f),
          cornerRadius = CornerRadius(2.dp.toPx()),
          style = stroke,
        )
      }
      else -> {
        drawCircle(color = color, style = stroke)
        drawLine(
          color,
          start = Offset(size.width * 0.32f, size.height * 0.32f),
          end = Offset(size.width * 0.68f, size.height * 0.68f),
          strokeWidth = 2.dp.toPx(),
          cap = StrokeCap.Round,
        )
      }
    }
  }
}

internal fun sessionColor(hex: String): Color {
  val value = hex.removePrefix("#").toLong(16)
  return Color(0xFF000000 or value)
}
