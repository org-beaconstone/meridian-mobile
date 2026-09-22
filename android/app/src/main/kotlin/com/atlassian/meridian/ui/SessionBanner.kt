package com.atlassian.meridian.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Authentication-screen session banner.
 *
 * Renders the signed-out, expiring and re-authenticating states (plus neutral checking and positive
 * active states) per the approved Figma concepts. It is a pure presentation component over an
 * already-resolved [SessionState]:
 *  - It NEVER blocks or delays the primary sign-in action — it is a sibling of the sign-in control,
 *    not a wrapper around it, and exposes no interactive elements that could intercept sign-in.
 *  - It has no dependency on the catalog fetch.
 *
 * Accessibility:
 *  - The banner is marked as an assertive-polite live region so TalkBack announces state changes
 *    even when focus is elsewhere (e.g. the user is typing in the sign-in field). We use
 *    [LiveRegionMode.Polite] to avoid interrupting the user's current action, satisfying the
 *    "announce, don't block" requirement.
 *  - Colors come from semantic [MeridianColors] tokens validated for WCAG 2.1 AA contrast in light
 *    and dark themes.
 *
 * @param state the resolved session state to present.
 * @param colors semantic color tokens; defaults to the current theme's tokens.
 */
@Composable
fun SessionBanner(
  state: SessionState,
  modifier: Modifier = Modifier,
  colors: MeridianColors = MeridianTheme.colors,
) {
  val content = SessionBannerContent.forState(state)
  val (background, foreground) = bannerColorsFor(state, colors)

  // A single announcement string keyed to the state so TalkBack reads a coherent status update.
  val announcement = "${content.title}. ${content.detail}"

  Row(
    modifier = modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(12.dp))
      .background(background)
      .padding(horizontal = 16.dp, vertical = 14.dp)
      // Live region: announce state changes through TalkBack without stealing focus from sign-in.
      .semantics {
        liveRegion = LiveRegionMode.Polite
        contentDescription = announcement
      },
    verticalAlignment = Alignment.Top,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    StatusDot(state = state, foreground = foreground)
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
      Text(
        text = content.title,
        color = foreground,
        fontWeight = FontWeight.SemiBold,
        fontSize = 15.sp,
      )
      Text(
        text = content.detail,
        color = foreground,
        fontSize = 13.sp,
      )
    }
  }
}

/**
 * Small leading status indicator. Purely decorative relative to the text (the text carries the
 * meaning and is what the live region announces), so it is hidden from the accessibility tree via
 * the parent's merged contentDescription.
 */
@Composable
private fun StatusDot(state: SessionState, foreground: Color) {
  val ring = when (state) {
    SessionState.Active -> foreground
    SessionState.Expiring -> foreground
    SessionState.SignedOut -> foreground
    SessionState.Reauthenticating -> foreground
    SessionState.Checking -> foreground
  }
  Box(
    modifier = Modifier
      .padding(top = 3.dp)
      .size(10.dp)
      .clip(CircleShape)
      .background(ring),
  )
}

private fun bannerColorsFor(state: SessionState, colors: MeridianColors): Pair<Color, Color> =
  when (state) {
    SessionState.Checking ->
      colors.bannerNeutralBackground to colors.bannerNeutralForeground
    SessionState.SignedOut ->
      colors.bannerSignedOutBackground to colors.bannerSignedOutForeground
    SessionState.Expiring ->
      colors.bannerExpiringBackground to colors.bannerExpiringForeground
    SessionState.Reauthenticating ->
      colors.bannerReauthBackground to colors.bannerReauthForeground
    SessionState.Active ->
      colors.bannerActiveBackground to colors.bannerActiveForeground
  }
