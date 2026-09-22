package com.atlassian.meridian

/**
 * Compose-free source of truth for the semantic design-token colour values.
 *
 * The Android UI ([com.atlassian.meridian.ui.MeridianTokens]) wraps these raw
 * ARGB values in Compose `Color`s. Keeping the numbers here means the WCAG 2.1
 * AA contrast of every semantic pair can be verified by the plain-JVM test
 * suite (see the contrast tests), without pulling in the Compose runtime.
 *
 * Each token is a light/dark pair of 0xAARRGGBB longs.
 */
object TokenPalette {
  data class Pair(val light: Long, val dark: Long)

  // Surfaces
  val background = Pair(0xFFFFFFFF, 0xFF0E1A20)
  val surface = Pair(0xFFF3F5F6, 0xFF16262E)
  val onSurface = Pair(0xFF11242B, 0xFFF2F5F6)
  val onSurfaceMuted = Pair(0xFF54646B, 0xFFAFC0C6)

  // Brand
  val brand = Pair(0xFF0B3C4C, 0xFF7FC7DC)
  val onBrand = Pair(0xFFFFFFFF, 0xFF06222B)

  // Status: informational (neutral / active session)
  val infoContainer = Pair(0xFFDCEBF2, 0xFF123642)
  val onInfoContainer = Pair(0xFF0B3040, 0xFFCDE6EF)

  // Status: warning (expiring session)
  val warningContainer = Pair(0xFFFDECC8, 0xFF4A3410)
  val onWarningContainer = Pair(0xFF5B4300, 0xFFFBE3B4)

  // Status: attention / error (signed out, catalog fetch failure)
  val errorContainer = Pair(0xFFFBDAD6, 0xFF551F1A)
  val onErrorContainer = Pair(0xFF7A1B12, 0xFFF7CFC9)

  // Status: progress (re-authenticating)
  val progressContainer = Pair(0xFFE3E0F3, 0xFF2D2A44)
  val onProgressContainer = Pair(0xFF352C6B, 0xFFD9D4F2)

  // Skeleton placeholder shimmer
  val skeleton = Pair(0xFFE2E7E9, 0xFF23343B)
  val skeletonHighlight = Pair(0xFFF2F5F6, 0xFF31454D)

  // Page indicator dots
  val indicatorActive = Pair(0xFF0B3C4C, 0xFF7FC7DC)
  val indicatorInactive = Pair(0xFFB9C6CB, 0xFF3C505A)
}
