package com.atlassian.meridian

import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/** Local payment-session clock for the rehearsal. This is not production authentication. */
const val SESSION_WARNING_WINDOW_MS: Long = 5 * 60 * 1000
const val PAYMENT_SESSION_TTL_MS: Long = 15 * 60 * 1000
const val SESSION_EXPIRING_MESSAGE = "Session expiring soon. Tap to extend."

enum class SessionPresence {
  HERE,
  ELSEWHERE,
  SIGNED_OUT,
}

enum class SessionBannerState {
  ACTIVE,
  EXPIRING_SOON,
  ACTIVE_ELSEWHERE,
  SIGNED_OUT,
}

sealed class SessionPhase {
  data class Banner(val state: SessionBannerState) : SessionPhase()
  data object Reauthenticate : SessionPhase()
}

data class PaymentSessionClock(
  val presence: SessionPresence,
  val expiresAtEpochMs: Long,
)

data class PaymentFormDraft(
  val recipientId: String,
  val amount: String,
  val reference: String,
  val method: PaymentMethod,
  val reviewing: Boolean,
  val idempotencyKey: String,
)

data class SessionRefreshResult(
  val draft: PaymentFormDraft,
  val session: PaymentSessionClock,
)

data class SessionBannerCopy(
  val message: String,
  val accessibilityLabel: String,
  val accessibilityHint: String,
  val indicator: String,
)

/** Atlassian light-theme tokens, the same values Meridian uses for semantic banners. */
data class SessionBannerPalette(
  val backgroundHex: String,
  val foregroundHex: String,
  val backgroundToken: String,
  val foregroundToken: String,
)

fun sessionPhase(presence: SessionPresence, expiresAtEpochMs: Long, nowEpochMs: Long): SessionPhase {
  if (presence == SessionPresence.SIGNED_OUT) return SessionPhase.Banner(SessionBannerState.SIGNED_OUT)
  if (nowEpochMs >= expiresAtEpochMs) return SessionPhase.Reauthenticate
  val remaining = expiresAtEpochMs - nowEpochMs
  if (remaining < SESSION_WARNING_WINDOW_MS) return SessionPhase.Banner(SessionBannerState.EXPIRING_SOON)
  if (presence == SessionPresence.ELSEWHERE) return SessionPhase.Banner(SessionBannerState.ACTIVE_ELSEWHERE)
  return SessionPhase.Banner(SessionBannerState.ACTIVE)
}

fun sessionRequiresReauthentication(presence: SessionPresence, expiresAtEpochMs: Long, nowEpochMs: Long): Boolean =
  sessionPhase(presence, expiresAtEpochMs, nowEpochMs) is SessionPhase.Reauthenticate

fun sessionRemainingDescription(remainingMillis: Long): String {
  val seconds = max(0, (remainingMillis / 1000).toInt())
  val minutes = seconds / 60
  val rest = seconds % 60
  if (minutes > 0 && rest == 0) return if (minutes == 1) "1 minute" else "$minutes minutes"
  if (minutes > 0) return "$minutes minutes $rest seconds"
  return "$seconds seconds"
}

fun sessionBannerCopy(state: SessionBannerState, remainingMillis: Long? = null): SessionBannerCopy {
  val hint = "Refreshes the session in place and keeps the payment details you entered."
  return when (state) {
    SessionBannerState.ACTIVE -> SessionBannerCopy(
      message = "Session active.",
      accessibilityLabel = "Session active.",
      accessibilityHint = hint,
      indicator = "check",
    )
    SessionBannerState.EXPIRING_SOON -> {
      val suffix = remainingMillis?.let { " ${sessionRemainingDescription(it)} remaining." } ?: ""
      SessionBannerCopy(
        message = SESSION_EXPIRING_MESSAGE,
        accessibilityLabel = SESSION_EXPIRING_MESSAGE + suffix,
        accessibilityHint = hint,
        indicator = "warning",
      )
    }
    SessionBannerState.ACTIVE_ELSEWHERE -> SessionBannerCopy(
      message = "Session active on another device.",
      accessibilityLabel = "Session active on another device.",
      accessibilityHint = hint,
      indicator = "devices",
    )
    SessionBannerState.SIGNED_OUT -> SessionBannerCopy(
      message = "Signed out.",
      accessibilityLabel = "Signed out.",
      accessibilityHint = hint,
      indicator = "signed-out",
    )
  }
}

fun sessionBannerPalette(state: SessionBannerState): SessionBannerPalette = when (state) {
  SessionBannerState.ACTIVE -> SessionBannerPalette(
    backgroundHex = "#EFFFD6",
    foregroundHex = "#4C6B1F",
    backgroundToken = "color.background.success",
    foregroundToken = "color.text.success",
  )
  SessionBannerState.EXPIRING_SOON -> SessionBannerPalette(
    backgroundHex = "#FFF5DB",
    foregroundHex = "#9E4C00",
    backgroundToken = "color.background.warning",
    foregroundToken = "color.text.warning",
  )
  SessionBannerState.ACTIVE_ELSEWHERE -> SessionBannerPalette(
    backgroundHex = "#E9F2FE",
    foregroundHex = "#1558BC",
    backgroundToken = "color.background.information",
    foregroundToken = "color.text.information",
  )
  SessionBannerState.SIGNED_OUT -> SessionBannerPalette(
    backgroundHex = "#FFECEB",
    foregroundHex = "#AE2E24",
    backgroundToken = "color.background.danger",
    foregroundToken = "color.text.danger",
  )
}

fun contrastRatio(foregroundHex: String, backgroundHex: String): Double {
  fun luminance(hex: String): Double {
    val channels = hexChannels(hex)
    fun linear(channel: Double) =
      if (channel <= 0.04045) channel / 12.92 else ((channel + 0.055) / 1.055).pow(2.4)
    return 0.2126 * linear(channels[0]) + 0.7152 * linear(channels[1]) + 0.0722 * linear(channels[2])
  }
  val lighter = max(luminance(foregroundHex), luminance(backgroundHex))
  val darker = min(luminance(foregroundHex), luminance(backgroundHex))
  return (lighter + 0.05) / (darker + 0.05)
}

fun refreshSessionInPlace(
  draft: PaymentFormDraft,
  session: PaymentSessionClock,
  nowEpochMs: Long,
  ttlMillis: Long = PAYMENT_SESSION_TTL_MS,
): SessionRefreshResult = SessionRefreshResult(
  draft = draft,
  session = PaymentSessionClock(
    presence = SessionPresence.HERE,
    expiresAtEpochMs = nowEpochMs + ttlMillis,
  ),
)

private fun hexChannels(hex: String): DoubleArray {
  val cleaned = hex.removePrefix("#")
  val value = cleaned.toLong(16)
  return doubleArrayOf(
    ((value shr 16) and 0xFF) / 255.0,
    ((value shr 8) and 0xFF) / 255.0,
    (value and 0xFF) / 255.0,
  )
}
