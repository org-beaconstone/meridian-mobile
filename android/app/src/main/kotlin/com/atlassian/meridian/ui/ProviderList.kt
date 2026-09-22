package com.atlassian.meridian.ui

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.atlassian.meridian.Provider

/**
 * Payment provider list section for the authentication/payment screen, including its net-new
 * loading skeleton and inline error/retry pattern.
 *
 * These are net-new components (no shared design-system equivalents in meridian-mobile). The section
 * follows the spec's async rules:
 *  - While the catalog is fetching for the first time, show a skeleton loader — never a spinner over
 *    stale data.
 *  - On fetch failure, keep the last known provider list visible with a NON-blocking inline error
 *    and a retry action.
 *  - Zero providers renders an explicit empty state, not an empty list.
 *
 * The provider baseline remains two providers (Adyen card / Worldpay bank); this component simply
 * renders whatever the catalog returns and truncates long names/descriptions gracefully.
 */
@Composable
fun ProviderListSection(
  providers: List<Provider>,
  isInitialLoading: Boolean,
  errorMessage: String?,
  onRetry: () -> Unit,
  modifier: Modifier = Modifier,
  colors: MeridianColors = MeridianTheme.colors,
) {
  Column(
    modifier = modifier.fillMaxWidth(),
    verticalArrangement = Arrangement.spacedBy(10.dp),
  ) {
    Text(
      text = "Payment methods",
      color = colors.onSurface,
      fontWeight = FontWeight.SemiBold,
      fontSize = 16.sp,
    )

    when {
      // First load with nothing to show yet: skeleton, never a spinner over stale data.
      isInitialLoading && providers.isEmpty() -> {
        ProviderSkeleton(colors = colors)
        ProviderSkeleton(colors = colors)
      }

      // Loaded successfully but empty: explicit, visibly-wrong empty state.
      providers.isEmpty() -> {
        Text(
          text = "No payment methods available right now",
          color = colors.onSurfaceMuted,
          fontSize = 14.sp,
        )
      }

      else -> {
        providers.forEach { provider ->
          ProviderRow(provider = provider, colors = colors)
        }
      }
    }

    // Non-blocking inline error + retry. Rendered beneath the (still visible) last-known list.
    if (errorMessage != null) {
      InlineErrorRetry(message = errorMessage, onRetry = onRetry, colors = colors)
    }
  }
}

@Composable
private fun ProviderRow(provider: Provider, colors: MeridianColors) {
  Column(
    modifier = Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(10.dp))
      .background(colors.surface)
      .padding(14.dp),
    verticalArrangement = Arrangement.spacedBy(2.dp),
  ) {
    Text(
      text = provider.name,
      color = colors.onSurface,
      fontWeight = FontWeight.Medium,
      fontSize = 15.sp,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
    )
    Text(
      text = provider.description,
      color = colors.onSurfaceMuted,
      fontSize = 13.sp,
      maxLines = 2,
      overflow = TextOverflow.Ellipsis,
    )
  }
}

/** Net-new shimmering skeleton row shown during the first catalog fetch. */
@Composable
fun ProviderSkeleton(
  modifier: Modifier = Modifier,
  colors: MeridianColors = MeridianTheme.colors,
) {
  val transition = rememberInfiniteTransition(label = "skeleton")
  val shimmer by transition.animateFloat(
    initialValue = 0.35f,
    targetValue = 0.85f,
    animationSpec = infiniteRepeatable(
      animation = tween(durationMillis = 900),
      repeatMode = RepeatMode.Reverse,
    ),
    label = "shimmerAlpha",
  )
  Column(
    modifier = modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(10.dp))
      .background(colors.surface)
      .padding(14.dp),
    verticalArrangement = Arrangement.spacedBy(8.dp),
  ) {
    Box(
      Modifier
        .height(14.dp)
        .fillMaxWidth(0.5f)
        .clip(RoundedCornerShape(4.dp))
        .alpha(shimmer)
        .background(colors.skeleton),
    )
    Box(
      Modifier
        .height(12.dp)
        .fillMaxWidth(0.8f)
        .clip(RoundedCornerShape(4.dp))
        .alpha(shimmer)
        .background(colors.skeleton),
    )
  }
}

/** Net-new non-blocking inline error with a retry action. */
@Composable
fun InlineErrorRetry(
  message: String,
  onRetry: () -> Unit,
  modifier: Modifier = Modifier,
  colors: MeridianColors = MeridianTheme.colors,
) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(10.dp))
      .background(colors.errorBackground)
      .padding(horizontal = 14.dp, vertical = 10.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Text(
      text = message,
      color = colors.onErrorBackground,
      fontSize = 13.sp,
      modifier = Modifier.weight(1f),
    )
    Spacer(Modifier.width(8.dp))
    TextButton(onClick = onRetry) {
      Text("Retry", color = colors.onErrorBackground, fontWeight = FontWeight.SemiBold)
    }
  }
}
