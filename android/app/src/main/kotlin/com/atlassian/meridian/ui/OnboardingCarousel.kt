package com.atlassian.meridian.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** A single onboarding page: an illustration slot, a header and a body line. */
data class OnboardingPage(
  val title: String,
  val body: String,
  val illustration: (@Composable (Modifier) -> Unit)? = null,
)

/**
 * Net-new onboarding carousel component (container + paging behaviour).
 *
 * Provides horizontally-paged, snap-to-page content with a page indicator.
 * Built on [LazyRow] + a snap fling behaviour so it needs no extra gradle
 * dependency beyond the Compose foundation the app already uses. Each page is
 * laid out to the full available width so paging feels like discrete pages.
 *
 * Accessibility: the paging container is described as a carousel, and the
 * page indicator announces "Page N of M".
 */
@Composable
fun OnboardingCarousel(
  pages: List<OnboardingPage>,
  modifier: Modifier = Modifier,
) {
  if (pages.isEmpty()) return
  val listState = rememberLazyListState()
  val flingBehavior = rememberSnapFlingBehavior(lazyListState = listState)
  val selected by remember {
    derivedStateOf {
      // The item whose leading edge is closest to (or past) the viewport start.
      val layout = listState.layoutInfo
      val viewportStart = layout.viewportStartOffset
      layout.visibleItemsInfo.minByOrNull { kotlin.math.abs(it.offset - viewportStart) }?.index
        ?: listState.firstVisibleItemIndex
    }
  }

  Column(
    modifier = modifier.semantics { contentDescription = "Onboarding carousel" },
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.spacedBy(16.dp),
  ) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
      val pageWidth = maxWidth
      LazyRow(
        state = listState,
        flingBehavior = flingBehavior,
      ) {
        items(count = pages.size) { index ->
          OnboardingPageView(
            page = pages[index],
            modifier = Modifier.width(pageWidth),
          )
        }
      }
    }
    PageIndicator(count = pages.size, selected = selected.coerceIn(0, pages.size - 1))
  }
}

@Composable
private fun OnboardingPageView(page: OnboardingPage, modifier: Modifier = Modifier) {
  val dark = isSystemInDarkTheme()
  Column(
    modifier = modifier.padding(horizontal = 8.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.spacedBy(14.dp),
  ) {
    val illustration = page.illustration
    if (illustration != null) {
      illustration(
        Modifier
          .fillMaxWidth()
          .height(160.dp)
          .clip(RoundedCornerShape(16.dp)),
      )
    } else {
      Box(
        Modifier
          .fillMaxWidth()
          .height(160.dp)
          .clip(RoundedCornerShape(16.dp))
          .background(MeridianTokens.surface.resolve(dark)),
      )
    }
    Text(
      text = page.title,
      color = MeridianTokens.onSurface.resolve(dark),
      fontWeight = FontWeight.SemiBold,
      fontSize = 20.sp,
      textAlign = TextAlign.Center,
    )
    Text(
      text = page.body,
      color = MeridianTokens.onSurfaceMuted.resolve(dark),
      fontSize = 14.sp,
      textAlign = TextAlign.Center,
    )
  }
}
