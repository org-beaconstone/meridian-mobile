package com.atlassian.meridian.ui

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp

/**
 * Net-new page indicator (dots) component.
 *
 * Renders [count] dots and grows/highlights the [selected] one. Colours come
 * from shared semantic tokens ([MeridianTokens.indicatorActive] /
 * [indicatorInactive]) so the contrast holds in light and dark themes.
 *
 * Accessibility: the row exposes a single, human-readable
 * "Page N of M" description instead of announcing each decorative dot.
 */
@Composable
fun PageIndicator(
  count: Int,
  selected: Int,
  modifier: Modifier = Modifier,
) {
  if (count <= 0) return
  val dark = isSystemInDarkTheme()
  val active = MeridianTokens.indicatorActive.resolve(dark)
  val inactive = MeridianTokens.indicatorInactive.resolve(dark)

  Row(
    modifier = modifier.clearAndSetSemantics {
      contentDescription = "Page ${selected + 1} of $count"
    },
    horizontalArrangement = Arrangement.spacedBy(8.dp),
  ) {
    for (index in 0 until count) {
      val isActive = index == selected
      val width by animateDpAsState(
        targetValue = if (isActive) 20.dp else 8.dp,
        label = "indicatorWidth",
      )
      Row(
        modifier = Modifier
          .height(8.dp)
          .then(if (isActive) Modifier.width(width) else Modifier.size(8.dp))
          .clip(if (isActive) RoundedCornerShape(4.dp) else CircleShape)
          .background(if (isActive) active else inactive),
      ) {}
    }
  }
}
