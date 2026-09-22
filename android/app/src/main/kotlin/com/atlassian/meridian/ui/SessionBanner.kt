package com.atlassian.meridian.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.atlassian.meridian.SessionState

/**
 * Resolved, theme-aware colours and copy for a single session banner state.
 * Kept separate from the composable so the copy + token mapping can be unit
 * tested without a Compose runtime.
 */
data class SessionBannerStyle(
  val container: SemanticColor,
  val onContainer: SemanticColor,
  val title: String,
  val body: String,
) {
  companion object {
    fun forState(state: SessionState): SessionBannerStyle? = when (state) {
      // Neutral while the initial session check resolves. No banner chrome is
      // needed for the transient checking state beyond a quiet placeholder.
      SessionState.checking -> SessionBannerStyle(
        container = MeridianTokens.surface,
        onContainer = MeridianTokens.onSurfaceMuted,
        title = "Checking your session",
        body = "Hang tight while we confirm you're signed in.",
      )
      SessionState.active -> SessionBannerStyle(
        container = MeridianTokens.infoContainer,
        onContainer = MeridianTokens.onInfoContainer,
        title = "You're signed in",
        body = "Your session is active. You're ready to make a payment.",
      )
      SessionState.expiring -> SessionBannerStyle(
        container = MeridianTokens.warningContainer,
        onContainer = MeridianTokens.onWarningContainer,
        title = "Your session is expiring soon",
        body = "Sign in again to avoid interrupting a payment.",
      )
      SessionState.signedOut -> SessionBannerStyle(
        container = MeridianTokens.errorContainer,
        onContainer = MeridianTokens.onErrorContainer,
        title = "You're signed out",
        body = "Sign in to see your account and make a payment.",
      )
      SessionState.reauthenticating -> SessionBannerStyle(
        container = MeridianTokens.progressContainer,
        onContainer = MeridianTokens.onProgressContainer,
        title = "Re-authenticating",
        body = "We're restoring your session. You can still sign in.",
      )
    }
  }
}

/** The spoken announcement for a state change, used by the TalkBack live region. */
fun sessionBannerAnnouncement(state: SessionState): String {
  val style = SessionBannerStyle.forState(state) ?: return ""
  return "${style.title}. ${style.body}"
}

/**
 * The revamped authentication session banner.
 *
 * Renders the signed-out, expiring and re-authenticating states (plus the
 * active and neutral checking states) using shared semantic design tokens so
 * light and dark themes both meet WCAG 2.1 AA contrast.
 *
 * Accessibility: the banner is marked as a TalkBack live region
 * ([LiveRegionMode.Polite]) so that when the session state changes the new
 * status is announced automatically without stealing focus from, blocking, or
 * delaying the primary sign-in action.
 *
 * This is a pure presentation of [state]; it performs no network calls and is
 * independent of the payment catalog fetch.
 */
@Composable
fun SessionBanner(
  state: SessionState,
  modifier: Modifier = Modifier,
) {
  val style = SessionBannerStyle.forState(state) ?: return
  val dark = isSystemInDarkTheme()
  val container = style.container.resolve(dark)
  val onContainer = style.onContainer.resolve(dark)

  Row(
    modifier = modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(12.dp))
      .background(container)
      .padding(horizontal = 16.dp, vertical = 12.dp)
      // Announce state changes through TalkBack without moving focus.
      .semantics {
        liveRegion = LiveRegionMode.Polite
        contentDescription = sessionBannerAnnouncement(state)
      },
    horizontalArrangement = Arrangement.spacedBy(12.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    StatusDot(color = onContainer)
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
      Text(
        text = style.title,
        color = onContainer,
        fontWeight = FontWeight.SemiBold,
        fontSize = 15.sp,
      )
      Text(
        text = style.body,
        color = onContainer,
        fontSize = 13.sp,
      )
    }
  }
}

@Composable
private fun StatusDot(color: Color) {
  Column(
    modifier = Modifier
      .size(10.dp)
      .clip(CircleShape)
      .background(color),
  ) {}
}
