package com.atlassian.meridian

import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * Payment-session health shown on the authentication screen.
 * Expired wins over every other signal. Active on another device wins over the
 * local expiry warning, because extending here would not move that other device.
 */
enum class SessionPhase {
  active,
  expiringSoon,
  activeElsewhere,
  expired,
}

object SessionTiming {
  /** Amber warning begins when this much time, or less, remains. */
  const val warningWindowMillis: Long = 5 * 60 * 1000

  /** Rehearsal payment session length after connect, extend, or re-authentication. */
  const val lifetimeMillis: Long = 15 * 60 * 1000

  /** WCAG target size requested for the extend and re-authenticate controls. */
  const val minimumTapTargetDp: Int = 48
}

object SessionBannerCopy {
  const val active = "Connected to secure payments platform"
  const val expiringSoon = "Session expiring soon. Tap to extend."
  const val activeElsewhere = "Session active on another device."
  const val expired = "Session expired. Please re-authenticate to confirm this transfer."

  fun text(phase: SessionPhase): String = when (phase) {
    SessionPhase.active -> active
    SessionPhase.expiringSoon -> expiringSoon
    SessionPhase.activeElsewhere -> activeElsewhere
    SessionPhase.expired -> expired
  }
}

data class SessionColor(val red: Int, val green: Int, val blue: Int)

data class SessionBannerTokens(
  val background: SessionColor,
  val foreground: SessionColor,
  val indicator: SessionColor,
)

/**
 * Palette taken from the Meridian mobile tokens: ink #142C35, sage #EAF0E5,
 * positive #387744, info #EDF4FF, focus #1868DB, danger #AE2A19, amber #F5C451.
 */
fun sessionBannerTokens(phase: SessionPhase): SessionBannerTokens = when (phase) {
  SessionPhase.active -> SessionBannerTokens(
    background = SessionColor(0xEA, 0xF0, 0xE5),
    foreground = SessionColor(0x14, 0x2C, 0x35),
    indicator = SessionColor(0x38, 0x77, 0x44),
  )
  SessionPhase.expiringSoon -> SessionBannerTokens(
    background = SessionColor(0xF5, 0xC4, 0x51),
    foreground = SessionColor(0x14, 0x2C, 0x35),
    indicator = SessionColor(0x14, 0x2C, 0x35),
  )
  SessionPhase.activeElsewhere -> SessionBannerTokens(
    background = SessionColor(0xED, 0xF4, 0xFF),
    foreground = SessionColor(0x14, 0x2C, 0x35),
    indicator = SessionColor(0x18, 0x68, 0xDB),
  )
  SessionPhase.expired -> SessionBannerTokens(
    background = SessionColor(0xAE, 0x2A, 0x19),
    foreground = SessionColor(0xFF, 0xFF, 0xFF),
    indicator = SessionColor(0xFF, 0xFF, 0xFF),
  )
}

fun resolveSessionPhase(nowMillis: Long, expiresAtMillis: Long, activeElsewhere: Boolean): SessionPhase {
  val remaining = expiresAtMillis - nowMillis
  if (remaining <= 0L) return SessionPhase.expired
  if (activeElsewhere) return SessionPhase.activeElsewhere
  if (remaining <= SessionTiming.warningWindowMillis) return SessionPhase.expiringSoon
  return SessionPhase.active
}

fun sessionBlocksInteraction(phase: SessionPhase): Boolean = phase == SessionPhase.expired

fun sessionOffersExtend(phase: SessionPhase): Boolean = phase == SessionPhase.expiringSoon

data class InFlightPaymentDraft(
  val recipientId: String,
  val amount: String,
  val reference: String,
  val method: PaymentMethod,
  val reviewing: Boolean,
  val idempotencyKey: String,
)

data class SessionRefresh(
  val draft: InFlightPaymentDraft,
  val expiresAtMillis: Long,
)

/** Moves the session deadline forward and returns the same payment draft. */
fun refreshSessionInPlace(
  draft: InFlightPaymentDraft,
  nowMillis: Long,
  lifetimeMillis: Long = SessionTiming.lifetimeMillis,
): SessionRefresh = SessionRefresh(draft, nowMillis + lifetimeMillis)

private fun srgbChannel(value: Int): Double {
  val channel = value / 255.0
  return if (channel <= 0.04045) channel / 12.92 else ((channel + 0.055) / 1.055).pow(2.4)
}

fun relativeLuminance(color: SessionColor): Double =
  (0.2126 * srgbChannel(color.red)) + (0.7152 * srgbChannel(color.green)) + (0.0722 * srgbChannel(color.blue))

fun contrastRatio(first: SessionColor, second: SessionColor): Double {
  val lighter = max(relativeLuminance(first), relativeLuminance(second))
  val darker = min(relativeLuminance(first), relativeLuminance(second))
  return (lighter + 0.05) / (darker + 0.05)
}
