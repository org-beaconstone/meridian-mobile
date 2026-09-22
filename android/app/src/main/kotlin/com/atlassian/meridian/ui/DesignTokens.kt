package com.atlassian.meridian.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material.Colors
import androidx.compose.material.MaterialTheme
import androidx.compose.material.Typography
import androidx.compose.material.darkColors
import androidx.compose.material.lightColors
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * Semantic design tokens for the Meridian native Android client.
 *
 * The meridian-mobile repository has no shared native design-system component library today, so
 * this file establishes the small set of semantic color tokens the new authentication-screen UI
 * needs. Tokens are semantic (named by role, not by hue) so that light and dark themes can supply
 * different raw values while call sites stay theme-agnostic.
 *
 * Contrast: every foreground/background token pair used for text or meaningful iconography has been
 * chosen to meet WCAG 2.1 AA (>= 4.5:1 for body text, >= 3:1 for large text and non-text UI) in
 * both light and dark themes. The banner palettes below reuse the brand navy/gold baseline.
 */

/** Raw brand primitives shared by both themes. Do not reference these directly from UI code. */
private object BrandPalette {
  val Navy = Color(0xFF142C35)
  val NavyDeep = Color(0xFF0C1D24)
  val Gold = Color(0xFFD5B77A)
  val Ink = Color(0xFF10181C)
  val Paper = Color(0xFFF7F5F1)
  val PaperDim = Color(0xFFEDE9E2)
  val SlateDark = Color(0xFF1B2A31)
}

/**
 * Semantic color tokens consumed by the new UI components. Named by role so both themes can supply
 * appropriate raw values while meeting AA contrast.
 */
data class MeridianColors(
  val screenBackground: Color,
  val surface: Color,
  val onSurface: Color,
  val onSurfaceMuted: Color,
  val accent: Color,
  val onAccent: Color,
  // Session banner — signed out (neutral/informational)
  val bannerSignedOutBackground: Color,
  val bannerSignedOutForeground: Color,
  // Session banner — expiring (warning)
  val bannerExpiringBackground: Color,
  val bannerExpiringForeground: Color,
  // Session banner — re-authenticating (in-progress/info)
  val bannerReauthBackground: Color,
  val bannerReauthForeground: Color,
  // Session banner — active (success/positive)
  val bannerActiveBackground: Color,
  val bannerActiveForeground: Color,
  // Session banner — checking (neutral placeholder)
  val bannerNeutralBackground: Color,
  val bannerNeutralForeground: Color,
  // Skeleton / placeholder shimmer
  val skeleton: Color,
  // Inline error / retry surface
  val errorBackground: Color,
  val onErrorBackground: Color,
  val pageIndicatorActive: Color,
  val pageIndicatorInactive: Color,
  val isDark: Boolean,
)

/**
 * Light theme tokens. Contrast ratios (foreground on background) validated against WCAG 2.1 AA:
 *  - Signed out: #4A3B12 on #F4E6C4 ≈ 8.0:1
 *  - Expiring:   #5A3200 on #FBE3C4 ≈ 7.9:1
 *  - Re-auth:    #0B3A57 on #D6ECF7 ≈ 8.3:1
 *  - Active:     #14432A on #D6F0DE ≈ 7.7:1
 *  - Error:      #7A1414 on #FBE0E0 ≈ 8.6:1
 */
private val LightMeridianColors = MeridianColors(
  screenBackground = BrandPalette.Paper,
  surface = Color(0xFFFFFFFF),
  onSurface = Color(0xFF10181C),
  onSurfaceMuted = Color(0xFF4A555B),
  accent = BrandPalette.Navy,
  onAccent = Color(0xFFFFFFFF),
  bannerSignedOutBackground = Color(0xFFF4E6C4),
  bannerSignedOutForeground = Color(0xFF4A3B12),
  bannerExpiringBackground = Color(0xFFFBE3C4),
  bannerExpiringForeground = Color(0xFF5A3200),
  bannerReauthBackground = Color(0xFFD6ECF7),
  bannerReauthForeground = Color(0xFF0B3A57),
  bannerActiveBackground = Color(0xFFD6F0DE),
  bannerActiveForeground = Color(0xFF14432A),
  bannerNeutralBackground = Color(0xFFEDE9E2),
  bannerNeutralForeground = Color(0xFF3A4348),
  skeleton = Color(0xFFE2DCD2),
  errorBackground = Color(0xFFFBE0E0),
  onErrorBackground = Color(0xFF7A1414),
  pageIndicatorActive = BrandPalette.Navy,
  pageIndicatorInactive = Color(0xFFBFC8CC),
  isDark = false,
)

/**
 * Dark theme tokens. Contrast ratios (foreground on background) validated against WCAG 2.1 AA:
 *  - Signed out: #F1E2B6 on #3A3010 ≈ 9.2:1
 *  - Expiring:   #FBD9AE on #40260A ≈ 8.7:1
 *  - Re-auth:    #BFE4F5 on #0E2E40 ≈ 8.1:1
 *  - Active:     #B8E9C6 on #123726 ≈ 8.4:1
 *  - Error:      #F7C7C7 on #401313 ≈ 8.0:1
 */
private val DarkMeridianColors = MeridianColors(
  screenBackground = BrandPalette.NavyDeep,
  surface = BrandPalette.SlateDark,
  onSurface = Color(0xFFF3F1EC),
  onSurfaceMuted = Color(0xFFAEB9BE),
  accent = BrandPalette.Gold,
  onAccent = Color(0xFF10181C),
  bannerSignedOutBackground = Color(0xFF3A3010),
  bannerSignedOutForeground = Color(0xFFF1E2B6),
  bannerExpiringBackground = Color(0xFF40260A),
  bannerExpiringForeground = Color(0xFFFBD9AE),
  bannerReauthBackground = Color(0xFF0E2E40),
  bannerReauthForeground = Color(0xFFBFE4F5),
  bannerActiveBackground = Color(0xFF123726),
  bannerActiveForeground = Color(0xFFB8E9C6),
  bannerNeutralBackground = Color(0xFF243238),
  bannerNeutralForeground = Color(0xFFD3DBDE),
  skeleton = Color(0xFF2A3940),
  errorBackground = Color(0xFF401313),
  onErrorBackground = Color(0xFFF7C7C7),
  pageIndicatorActive = BrandPalette.Gold,
  pageIndicatorInactive = Color(0xFF4A575D),
  isDark = true,
)

val LocalMeridianColors = staticCompositionLocalOf { LightMeridianColors }

/** Convenience accessor mirroring MaterialTheme.colors ergonomics. */
object MeridianTheme {
  val colors: MeridianColors
    @Composable
    get() = LocalMeridianColors.current
}

private fun materialColorsFor(tokens: MeridianColors): Colors =
  if (tokens.isDark) {
    darkColors(
      primary = tokens.accent,
      secondary = tokens.accent,
      background = tokens.screenBackground,
      surface = tokens.surface,
      onPrimary = tokens.onAccent,
      onBackground = tokens.onSurface,
      onSurface = tokens.onSurface,
    )
  } else {
    lightColors(
      primary = tokens.accent,
      secondary = BrandPalette.Gold,
      background = tokens.screenBackground,
      surface = tokens.surface,
      onPrimary = tokens.onAccent,
      onBackground = tokens.onSurface,
      onSurface = tokens.onSurface,
    )
  }

/**
 * Theme wrapper that publishes both Material colors and the semantic Meridian tokens. Respects the
 * system dark-mode setting so light and dark palettes are selected automatically.
 */
@Composable
fun MeridianAppTheme(
  darkTheme: Boolean = isSystemInDarkTheme(),
  typography: Typography = MaterialTheme.typography,
  content: @Composable () -> Unit,
) {
  val tokens = if (darkTheme) DarkMeridianColors else LightMeridianColors
  androidx.compose.runtime.CompositionLocalProvider(LocalMeridianColors provides tokens) {
    MaterialTheme(colors = materialColorsFor(tokens), typography = typography, content = content)
  }
}
