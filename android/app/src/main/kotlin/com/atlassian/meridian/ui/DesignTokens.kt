package com.atlassian.meridian.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color
import com.atlassian.meridian.TokenPalette

/**
 * Semantic design tokens for the Meridian native Android UI.
 *
 * These are the shared "design system" colour tokens referenced by the new
 * authentication / onboarding components. Each semantic token resolves to a
 * light and a dark value. The pairs below were chosen so that foreground
 * tokens meet WCAG 2.1 AA contrast (>= 4.5:1 for body text, >= 3:1 for large
 * text and non-text UI) against their intended background token in both
 * themes. See [DesignTokensContrast] and the SDK unit tests for the verified
 * ratios.
 *
 * There is no shared native design-system library in this repository yet, so
 * these tokens are the net-new foundation the new components build on rather
 * than a retrofit of an existing palette.
 */
data class SemanticColor(val light: Color, val dark: Color) {
  @Composable
  @ReadOnlyComposable
  fun resolve(): Color = if (isSystemInDarkTheme()) dark else light

  fun resolve(dark: Boolean): Color = if (dark) this.dark else this.light
}

/**
 * The palette of semantic tokens. Names describe intent (role), not raw hue,
 * so the same component works across light and dark themes.
 *
 * Values come from [TokenPalette] (a Compose-free source of truth in the SDK)
 * so the exact colours used here are the ones verified for WCAG 2.1 AA contrast
 * by the plain-JVM contrast tests.
 */
object MeridianTokens {
  private fun token(pair: TokenPalette.Pair) =
    SemanticColor(Color(pair.light), Color(pair.dark))

  // Surfaces
  val background = token(TokenPalette.background)
  val surface = token(TokenPalette.surface)
  val onSurface = token(TokenPalette.onSurface)
  val onSurfaceMuted = token(TokenPalette.onSurfaceMuted)

  // Brand
  val brand = token(TokenPalette.brand)
  val onBrand = token(TokenPalette.onBrand)

  // Status: informational (neutral / active session)
  val infoContainer = token(TokenPalette.infoContainer)
  val onInfoContainer = token(TokenPalette.onInfoContainer)

  // Status: warning (expiring session)
  val warningContainer = token(TokenPalette.warningContainer)
  val onWarningContainer = token(TokenPalette.onWarningContainer)

  // Status: attention / error (signed out, catalog fetch failure)
  val errorContainer = token(TokenPalette.errorContainer)
  val onErrorContainer = token(TokenPalette.onErrorContainer)

  // Status: progress (re-authenticating)
  val progressContainer = token(TokenPalette.progressContainer)
  val onProgressContainer = token(TokenPalette.onProgressContainer)

  // Skeleton placeholder shimmer
  val skeleton = token(TokenPalette.skeleton)
  val skeletonHighlight = token(TokenPalette.skeletonHighlight)

  // Page indicator dots
  val indicatorActive = token(TokenPalette.indicatorActive)
  val indicatorInactive = token(TokenPalette.indicatorInactive)
}
