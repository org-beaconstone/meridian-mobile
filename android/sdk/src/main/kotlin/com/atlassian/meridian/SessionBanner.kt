package com.atlassian.meridian

import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/** Payment-session health shown on the payment and authentication screen. */
enum class SessionBannerState {
  ACTIVE,
  EXPIRING_SOON,
  ACTIVE_ELSEWHERE,
  EXPIRED,
}

/** sRGB design token. Contrast is computed against WCAG 2.1 relative luminance. */
data class SessionColor(
  val token: String,
  val red: Int,
  val green: Int,
  val blue: Int,
) {
  fun relativeLuminance(): Double {
    fun channel(value: Int): Double {
      val c = value / 255.0
      return if (c <= 0.04045) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)
    }
    return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
  }

  fun contrastRatio(against: SessionColor): Double {
    val lighter = max(relativeLuminance(), against.relativeLuminance())
    val darker = min(relativeLuminance(), against.relativeLuminance())
    return (lighter + 0.05) / (darker + 0.05)
  }
}

/** In-flight transfer details that session refresh must carry through unchanged. */
data class InFlightPaymentDraft(
  val recipientId: String,
  val amount: String,
  val reference: String,
  val method: PaymentMethod,
  val reviewing: Boolean,
  val idempotencyKey: String,
)

data class SessionBannerPresentation(
  val state: SessionBannerState,
  val message: String,
  val accessibilityLabel: String,
  val accessibilityHint: String,
  val extendActionLabel: String?,
  val reauthenticateActionLabel: String?,
  val blocksInteraction: Boolean,
  val background: SessionColor,
  val foreground: SessionColor,
  val minimumTapTargetDp: Int,
) {
  fun contrastRatio(): Double = foreground.contrastRatio(background)

  /** Normal text needs 4.5:1. Tap targets are at least 48 dp. */
  fun meetsWcagAa(): Boolean =
    contrastRatio() >= 4.5 &&
      minimumTapTargetDp >= SessionBanner.MINIMUM_TAP_TARGET_DP &&
      message.isNotEmpty() &&
      accessibilityLabel == message
}

data class SessionRefreshResult(
  val presentation: SessionBannerPresentation,
  val draft: InFlightPaymentDraft,
  val expiresAtMs: Long,
  val activeElsewhere: Boolean,
)

/** Meridian session-banner tokens shared with the native payment screens. */
object SessionBanner {
  const val EXPIRING_WINDOW_MS: Long = 5L * 60L * 1000L
  const val DEFAULT_DURATION_MS: Long = 15L * 60L * 1000L
  const val MINIMUM_TAP_TARGET_DP: Int = 48

  const val CONNECTED_MESSAGE: String = "Connected to secure payments platform"
  const val EXPIRING_MESSAGE: String = "Session expiring soon. Tap to extend."
  const val ACTIVE_ELSEWHERE_MESSAGE: String = "Session active on another device."
  const val EXPIRED_MESSAGE: String = "Session expired. Please re-authenticate to confirm this transfer."
  const val EXTEND_ACTION: String = "Tap to extend"
  const val REAUTHENTICATE_ACTION: String = "Re-authenticate"

  const val EXTEND_HINT: String = "Refreshes this payment session and keeps the details and payment key already entered."
  const val REAUTHENTICATE_HINT: String = "Authenticates this session again and keeps the transfer details already entered."
  const val STATUS_HINT: String = "Payment session status."

  /** Brand ink #142C35 on sage #EAF0E5. */
  val activeBackground = SessionColor("color.background.subtle", 234, 240, 229)
  val textBrand = SessionColor("color.text.brand", 20, 44, 53)

  /** Amber warning surface #F6D98A. */
  val warningBackground = SessionColor("color.background.warning", 246, 217, 138)

  /** Info surface #EDF4FF for a session held on another device. */
  val infoBackground = SessionColor("color.background.info", 237, 244, 255)

  /** Danger surface #FFEDEB and danger text #8D2517. */
  val dangerBackground = SessionColor("color.background.danger", 255, 237, 235)
  val dangerText = SessionColor("color.text.danger", 141, 37, 23)

  fun nowMs(): Long = System.currentTimeMillis()

  /**
   * Expired wins over every other signal. Elsewhere is shown while time remains.
   * Expiring soon is the closed window of five minutes before timeout.
   */
  fun present(nowMs: Long, expiresAtMs: Long, activeElsewhere: Boolean): SessionBannerPresentation {
    val remaining = expiresAtMs - nowMs
    val state = when {
      remaining <= 0L -> SessionBannerState.EXPIRED
      activeElsewhere -> SessionBannerState.ACTIVE_ELSEWHERE
      remaining <= EXPIRING_WINDOW_MS -> SessionBannerState.EXPIRING_SOON
      else -> SessionBannerState.ACTIVE
    }

    val message: String
    val hint: String
    val background: SessionColor
    val foreground: SessionColor
    when (state) {
      SessionBannerState.ACTIVE -> {
        message = CONNECTED_MESSAGE
        hint = STATUS_HINT
        background = activeBackground
        foreground = textBrand
      }
      SessionBannerState.EXPIRING_SOON -> {
        message = EXPIRING_MESSAGE
        hint = EXTEND_HINT
        background = warningBackground
        foreground = textBrand
      }
      SessionBannerState.ACTIVE_ELSEWHERE -> {
        message = ACTIVE_ELSEWHERE_MESSAGE
        hint = STATUS_HINT
        background = infoBackground
        foreground = textBrand
      }
      SessionBannerState.EXPIRED -> {
        message = EXPIRED_MESSAGE
        hint = REAUTHENTICATE_HINT
        background = dangerBackground
        foreground = dangerText
      }
    }

    return SessionBannerPresentation(
      state = state,
      message = message,
      accessibilityLabel = message,
      accessibilityHint = hint,
      extendActionLabel = if (state == SessionBannerState.EXPIRING_SOON) EXTEND_ACTION else null,
      reauthenticateActionLabel = if (state == SessionBannerState.EXPIRED) REAUTHENTICATE_ACTION else null,
      blocksInteraction = state == SessionBannerState.EXPIRED,
      background = background,
      foreground = foreground,
      minimumTapTargetDp = MINIMUM_TAP_TARGET_DP,
    )
  }
}

object SessionRefresh {
  /** Moves expiry forward and returns the same payment draft. */
  fun extend(
    nowMs: Long,
    durationMs: Long = SessionBanner.DEFAULT_DURATION_MS,
    draft: InFlightPaymentDraft,
    activeElsewhere: Boolean,
  ): SessionRefreshResult {
    val expiresAtMs = nowMs + durationMs
    return SessionRefreshResult(
      presentation = SessionBanner.present(nowMs, expiresAtMs, activeElsewhere),
      draft = draft,
      expiresAtMs = expiresAtMs,
      activeElsewhere = activeElsewhere,
    )
  }

  /** Opens a new authentication window on this device without replacing the draft. */
  fun reauthenticate(
    nowMs: Long,
    durationMs: Long = SessionBanner.DEFAULT_DURATION_MS,
    draft: InFlightPaymentDraft,
  ): SessionRefreshResult {
    val expiresAtMs = nowMs + durationMs
    return SessionRefreshResult(
      presentation = SessionBanner.present(nowMs, expiresAtMs, activeElsewhere = false),
      draft = draft,
      expiresAtMs = expiresAtMs,
      activeElsewhere = false,
    )
  }

  /** Keeps the previous expiry and draft when refresh does not succeed. */
  fun retain(
    nowMs: Long,
    expiresAtMs: Long,
    activeElsewhere: Boolean,
    draft: InFlightPaymentDraft,
  ): SessionRefreshResult {
    return SessionRefreshResult(
      presentation = SessionBanner.present(nowMs, expiresAtMs, activeElsewhere),
      draft = draft,
      expiresAtMs = expiresAtMs,
      activeElsewhere = activeElsewhere,
    )
  }
}
