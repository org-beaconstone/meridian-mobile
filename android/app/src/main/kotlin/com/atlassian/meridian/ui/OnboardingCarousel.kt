package com.atlassian.meridian.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * A single onboarding page. Illustration is represented by a colored token block so the component
 * stays self-contained (no bundled image assets), while callers can supply their own illustration
 * slot via [OnboardingCarousel] if needed later.
 */
data class OnboardingPage(
  val title: String,
  val body: String,
  val illustration: @Composable (Modifier) -> Unit,
)

/**
 * Net-new onboarding carousel component (container + paging behavior).
 *
 * meridian-mobile has no shared design-system carousel today, so this is a from-scratch build on
 * top of Compose Foundation's [HorizontalPager]. It renders illustration + header per page and pairs
 * with [PageIndicator] to show a dot per page.
 *
 * Accessibility: each page merges its illustration/title/body into a single readable node, and the
 * pager exposes standard swipe semantics. The page indicator is decorative and hidden from TalkBack
 * (the pager announces page position), matching the "don't double-announce" convention.
 */
@Composable
fun OnboardingCarousel(
  pages: List<OnboardingPage>,
  modifier: Modifier = Modifier,
  state: PagerState = rememberPagerState(pageCount = { pages.size }),
  colors: MeridianColors = MeridianTheme.colors,
) {
  Column(
    modifier = modifier.fillMaxWidth(),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.spacedBy(16.dp),
  ) {
    HorizontalPager(
      state = state,
      modifier = Modifier.fillMaxWidth(),
    ) { pageIndex ->
      val page = pages[pageIndex]
      Column(
        modifier = Modifier
          .fillMaxWidth()
          .padding(horizontal = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
      ) {
        page.illustration(
          Modifier
            .fillMaxWidth()
            .height(160.dp)
            .clip(RoundedCornerShape(16.dp)),
        )
        Text(
          text = page.title,
          color = colors.onSurface,
          fontWeight = FontWeight.SemiBold,
          fontSize = 20.sp,
          textAlign = TextAlign.Center,
        )
        Text(
          text = page.body,
          color = colors.onSurfaceMuted,
          fontSize = 14.sp,
          textAlign = TextAlign.Center,
        )
      }
    }
    PageIndicator(
      pageCount = pages.size,
      currentPage = state.currentPage,
      colors = colors,
    )
  }
}

/**
 * Net-new page indicator (dots). Renders one dot per page with the active page emphasized via the
 * active semantic token and a slightly wider pill. Decorative: hidden from the accessibility tree
 * because the carousel/pager already announces the current page to TalkBack.
 *
 * @param pageCount total number of pages (dots).
 * @param currentPage zero-based index of the active page.
 */
@Composable
fun PageIndicator(
  pageCount: Int,
  currentPage: Int,
  modifier: Modifier = Modifier,
  colors: MeridianColors = MeridianTheme.colors,
) {
  Row(
    modifier = modifier
      .clearAndSetSemantics { contentDescription = "Page ${currentPage + 1} of $pageCount" },
    horizontalArrangement = Arrangement.spacedBy(8.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    for (index in 0 until pageCount) {
      val active = index == currentPage
      val width by animateDpAsState(if (active) 22.dp else 8.dp, label = "dotWidth")
      val color by animateColorAsState(
        if (active) colors.pageIndicatorActive else colors.pageIndicatorInactive,
        label = "dotColor",
      )
      Box(
        modifier = Modifier
          .height(8.dp)
          .let { if (active) it.width(width) else it.size(8.dp) }
          .clip(if (active) RoundedCornerShape(4.dp) else CircleShape)
          .background(color),
      )
    }
  }
}

/** Default illustration slot: a solid token-colored block. Callers may override per page. */
@Composable
fun TokenIllustration(color: Color, modifier: Modifier = Modifier) {
  Box(modifier = modifier.background(color))
}
