package com.atlassian.meridian.ui

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.Text
import androidx.compose.material.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.atlassian.meridian.Provider

/**
 * Net-new payment provider loading skeleton.
 *
 * Shows shimmering placeholder rows while the provider catalog fetches, so the
 * screen never shows a spinner over stale data. Uses semantic skeleton tokens
 * that keep adequate contrast in both themes.
 */
@Composable
fun ProviderSkeleton(
  modifier: Modifier = Modifier,
  rows: Int = 3,
) {
  val dark = isSystemInDarkTheme()
  val base = MeridianTokens.skeleton.resolve(dark)
  val highlight = MeridianTokens.skeletonHighlight.resolve(dark)
  val transition = rememberInfiniteTransition(label = "skeleton")
  val progress by transition.animateFloat(
    initialValue = 0f,
    targetValue = 1f,
    animationSpec = infiniteRepeatable(
      animation = tween(durationMillis = 900),
      repeatMode = RepeatMode.Reverse,
    ),
    label = "skeletonShimmer",
  )
  val shimmer = lerp(base, highlight, progress)

  Column(
    modifier = modifier
      .fillMaxWidth()
      .semantics { contentDescription = "Loading payment methods" },
    verticalArrangement = Arrangement.spacedBy(10.dp),
  ) {
    repeat(rows) {
      Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Box(
          Modifier
            .height(20.dp)
            .width(20.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(shimmer),
        )
        Column(
          Modifier.weight(1f),
          verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
          Box(
            Modifier
              .fillMaxWidth(0.6f)
              .height(14.dp)
              .clip(RoundedCornerShape(4.dp))
              .background(shimmer),
          )
          Box(
            Modifier
              .fillMaxWidth(0.85f)
              .height(12.dp)
              .clip(RoundedCornerShape(4.dp))
              .background(shimmer.copy(alpha = 0.7f)),
          )
        }
      }
    }
  }
}
/**
 * Net-new inline, non-blocking error + retry pattern for the provider catalog.
 *
 * A failed fetch keeps the last known list visible (rendered by the caller);
 * this component is the accompanying inline error strip with a retry action.
 * It is a polite TalkBack live region so the error is announced without
 * grabbing focus.
 */
@Composable
fun ProviderErrorRetry(
  message: String,
  onRetry: () -> Unit,
  modifier: Modifier = Modifier,
  enabled: Boolean = true,
) {
  val dark = isSystemInDarkTheme()
  val container = MeridianTokens.errorContainer.resolve(dark)
  val onContainer = MeridianTokens.onErrorContainer.resolve(dark)
  Row(
    modifier = modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(10.dp))
      .background(container)
      .padding(horizontal = 14.dp, vertical = 8.dp)
      .semantics {
        liveRegion = LiveRegionMode.Polite
        contentDescription = "$message. Retry available."
      },
    horizontalArrangement = Arrangement.SpaceBetween,
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Text(text = message, color = onContainer, fontSize = 13.sp)
    TextButton(onClick = onRetry, enabled = enabled) {
      Text("Retry", color = onContainer, fontWeight = FontWeight.SemiBold)
    }
  }
}

/**
 * Net-new empty state: shown when the catalog returns zero providers. This
 * should never happen in production, so it is intentionally explicit rather
 * than a silently empty list.
 */
@Composable
fun ProviderEmptyState(modifier: Modifier = Modifier) {
  val dark = isSystemInDarkTheme()
  Box(
    modifier = modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(10.dp))
      .border(1.dp, MeridianTokens.onSurfaceMuted.resolve(dark), RoundedCornerShape(10.dp))
      .padding(16.dp),
  ) {
    Text(
      text = "No payment methods available right now",
      color = MeridianTokens.onSurface.resolve(dark),
      fontSize = 14.sp,
    )
  }
}

/**
 * A live provider row. Provider names/descriptions truncate gracefully; the
 * list makes no assumption about a fixed maximum number of providers.
 */
@Composable
fun ProviderRow(provider: Provider, modifier: Modifier = Modifier) {
  val dark = isSystemInDarkTheme()
  Column(
    modifier = modifier.fillMaxWidth(),
    verticalArrangement = Arrangement.spacedBy(2.dp),
  ) {
    Text(
      text = provider.name,
      color = MeridianTokens.onSurface.resolve(dark),
      fontWeight = FontWeight.Medium,
      fontSize = 15.sp,
      maxLines = 1,
    )
    Text(
      text = provider.description,
      color = MeridianTokens.onSurfaceMuted.resolve(dark),
      fontSize = 13.sp,
      maxLines = 2,
    )
  }
}
