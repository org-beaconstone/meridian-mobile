package com.atlassian.meridian

import kotlin.math.max
import kotlin.math.pow

/** Visual session states for the payment and authentication screen. */
enum class SessionVisualState {
  Active,
  Expiring,
  ActiveElsewhere,
  SignedOut,
  Expired,
  Unknown,
}

enum class SessionProbeResult {
  NotSignedIn,
  Confirmed,
  Unreachable,
  Rejected,
}

sealed class SessionFailure {
  data object Timeout : SessionFailure()
  data object Unauthorized : SessionFailure()
  data class Http(val statusCode: Int) : SessionFailure()
  data object Other : SessionFailure()
}

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
    val darker = minOf(relativeLuminance(), against.relativeLuminance())
    return (lighter + 0.05) / (darker + 0.05)
  }
}

data class PaymentContext(
  val recipientId: String,
  val amount: String,
  val reference: String,
  val method: PaymentMethod,
  val reviewing: Boolean,
  val idempotencyKey: String,
)

data class SessionClock(
  val sessionId: String? = null,
  val expiresAtMs: Long? = null,
  val activeElsewhere: Boolean = false,
  val probe: SessionProbeResult = SessionProbeResult.NotSignedIn,
)

data class SessionTransition(
  val clock: SessionClock,
  val context: PaymentContext,
) {
  val method: PaymentMethod get() = context.method
  val idempotencyKey: String get() = context.idempotencyKey
  val provider: ProviderId get() = SessionBanner.providerBaseline(context.method)
}

data class SessionBannerPresentation(
  val state: SessionVisualState,
  val title: String,
  val message: String,
  val accessibilityLabel: String,
  val accessibilityHint: String,
  val actionLabel: String?,
  val actionAccessibilityLabel: String?,
  val blocksPaymentEntry: Boolean,
  val background: SessionColor,
  val foreground: SessionColor,
  val actionBackground: SessionColor?,
  val actionForeground: SessionColor?,
) {
  fun meetsWcagAa(scale: SessionTextScale = SessionTextScale(1.0)): Boolean {
    val text = foreground.contrastRatio(background) >= SessionBanner.minimumContrast
    val action = if (actionBackground != null && actionForeground != null && actionLabel != null) {
      actionForeground.contrastRatio(actionBackground) >= SessionBanner.minimumContrast
    } else {
      actionLabel == null
    }
    return text &&
      action &&
      scale.tapTargetPoints >= SessionBanner.minimumTapTargetPoints &&
      scale.wraps &&
      title.isNotEmpty() &&
      message.isNotEmpty() &&
      accessibilityLabel.contains(message)
  }
}

data class SessionTextScale(val fontScale: Double) {
  private val scale = max(0.5, fontScale)
  val titlePoints: Double = 15 * scale
  val bodyPoints: Double = 13 * scale
  val tapTargetPoints: Double = max(SessionBanner.minimumTapTargetPoints, 48 * scale)
  val wraps: Boolean = true
}

data class SessionProbePayload(
  val healthy: Boolean,
  val activeElsewhere: Boolean,
)

object SessionAccessibility {
  const val banner = "payment.sessionBanner"
  const val action = "payment.sessionBanner.action"
  const val endpoint = "auth.endpoint"
  const val room = "auth.room"
  const val connect = "auth.connect"
  const val paymentForm = "payment.form"

  fun focusOrder(showsAction: Boolean): List<String> {
    val order = mutableListOf(banner)
    if (showsAction) order += action
    order += listOf(endpoint, room, connect, paymentForm)
    return order
  }
}

object SessionBanner {
  const val expiringWindowMs: Long = 5 * 60 * 1000
  const val defaultDurationMs: Long = 15 * 60 * 1000
  const val minimumTapTargetPoints: Double = 48.0
  const val minimumContrast: Double = 4.5

  val textBrand = SessionColor("color.text.brand", 20, 44, 53)
  val surfaceSubtle = SessionColor("color.background.subtle", 234, 240, 229)
  val surfaceWarning = SessionColor("color.background.warning", 246, 217, 138)
  val surfaceInfo = SessionColor("color.background.info", 237, 244, 255)
  val surfaceSignedOut = SessionColor("color.background.signedOut", 248, 230, 227)
  val textSignedOut = SessionColor("color.text.signedOut", 111, 29, 22)
  val surfaceExpired = SessionColor("color.background.expired", 243, 208, 203)
  val textExpired = SessionColor("color.text.expired", 92, 17, 12)
  val surfaceUnknown = SessionColor("color.background.neutral", 231, 235, 228)
  val textUnknown = SessionColor("color.text.neutral", 28, 43, 36)
  val actionInk = SessionColor("color.action.inverse", 248, 249, 246)

  fun nowMs(): Long = System.currentTimeMillis()

  fun providerBaseline(method: PaymentMethod): ProviderId = when (method) {
    PaymentMethod.card -> ProviderId.adyen
    PaymentMethod.bank -> ProviderId.worldpay
  }

  fun hasSession(clock: SessionClock): Boolean =
    !clock.sessionId.isNullOrBlank()

  fun resolve(nowMs: Long, clock: SessionClock): SessionVisualState {
    if (!hasSession(clock) || clock.probe == SessionProbeResult.NotSignedIn || clock.probe == SessionProbeResult.Rejected) {
      return SessionVisualState.SignedOut
    }
    if (clock.probe == SessionProbeResult.Unreachable) {
      return SessionVisualState.Unknown
    }
    val expiresAtMs = clock.expiresAtMs ?: return SessionVisualState.Unknown
    val remaining = expiresAtMs - nowMs
    if (remaining <= 0) return SessionVisualState.Expired
    if (clock.activeElsewhere) return SessionVisualState.ActiveElsewhere
    if (remaining <= expiringWindowMs) return SessionVisualState.Expiring
    return SessionVisualState.Active
  }

  fun formatRemaining(ms: Long): String {
    val positive = max(ms, 0L)
    val totalSeconds = (positive + 999) / 1000
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return when {
      minutes > 0 && seconds > 0 -> "$minutes min $seconds sec"
      minutes > 0 -> "$minutes min"
      else -> "$seconds sec"
    }
  }

  fun present(nowMs: Long, clock: SessionClock): SessionBannerPresentation {
    val state = resolve(nowMs, clock)
    val remaining = clock.expiresAtMs?.let { it - nowMs }

    val title: String
    val message: String
    val hint: String
    val actionLabel: String?
    val actionAccessibilityLabel: String?
    val background: SessionColor
    val foreground: SessionColor
    val actionBackground: SessionColor?
    val actionForeground: SessionColor?

    when (state) {
      SessionVisualState.Active -> {
        title = "Session active"
        message = "You're securely signed in."
        hint = "Payment session status."
        actionLabel = null
        actionAccessibilityLabel = null
        background = surfaceSubtle
        foreground = textBrand
        actionBackground = null
        actionForeground = null
      }
      SessionVisualState.Expiring -> {
        val time = formatRemaining(remaining ?: 0)
        title = "Session expiring"
        message = "Your session expires in $time."
        hint = "Refreshes this session and keeps the payment details and idempotency key already entered."
        actionLabel = "Refresh"
        actionAccessibilityLabel = "Refresh session"
        background = surfaceWarning
        foreground = textBrand
        actionBackground = textBrand
        actionForeground = actionInk
      }
      SessionVisualState.ActiveElsewhere -> {
        title = "Active on another device"
        message = if (remaining != null && remaining > 0 && remaining <= expiringWindowMs) {
          "This session is active on another device. It expires in ${formatRemaining(remaining)}."
        } else {
          "This session is active on another device."
        }
        hint = "Payment session status. Entered payment details stay on this device."
        actionLabel = null
        actionAccessibilityLabel = null
        background = surfaceInfo
        foreground = textBrand
        actionBackground = null
        actionForeground = null
      }
      SessionVisualState.SignedOut -> {
        title = "Signed out"
        message = "You've been signed out. Sign in to continue."
        hint = "Signs in to the selected session and keeps the payment details already entered."
        actionLabel = "Sign in"
        actionAccessibilityLabel = "Sign in to this session"
        background = surfaceSignedOut
        foreground = textSignedOut
        actionBackground = textSignedOut
        actionForeground = actionInk
      }
      SessionVisualState.Expired -> {
        title = "Session expired"
        message = "This session has expired. Refresh to continue. Your payment details are still here."
        hint = "Refreshes this session and keeps the amount, recipient, reference, method, and payment key."
        actionLabel = "Refresh"
        actionAccessibilityLabel = "Refresh session"
        background = surfaceExpired
        foreground = textExpired
        actionBackground = textExpired
        actionForeground = actionInk
      }
      SessionVisualState.Unknown -> {
        title = "Session not confirmed"
        message = "We couldn't confirm this session. Your payment details are still here."
        hint = "Checks the same session again and keeps the payment details and payment key already entered."
        actionLabel = "Try again"
        actionAccessibilityLabel = "Try again to confirm this session"
        background = surfaceUnknown
        foreground = textUnknown
        actionBackground = textUnknown
        actionForeground = actionInk
      }
    }

    return SessionBannerPresentation(
      state = state,
      title = title,
      message = message,
      accessibilityLabel = "$title. $message",
      accessibilityHint = hint,
      actionLabel = actionLabel,
      actionAccessibilityLabel = actionAccessibilityLabel,
      blocksPaymentEntry = false,
      background = background,
      foreground = foreground,
      actionBackground = actionBackground,
      actionForeground = actionForeground,
    )
  }
}

object SessionActions {
  fun signIn(
    nowMs: Long,
    sessionId: String,
    context: PaymentContext,
    durationMs: Long = SessionBanner.defaultDurationMs,
  ): SessionTransition = SessionTransition(
    clock = SessionClock(
      sessionId = sessionId,
      expiresAtMs = nowMs + durationMs,
      activeElsewhere = false,
      probe = SessionProbeResult.Confirmed,
    ),
    context = context,
  )

  fun refresh(
    nowMs: Long,
    clock: SessionClock,
    context: PaymentContext,
    activeElsewhere: Boolean,
    durationMs: Long = SessionBanner.defaultDurationMs,
  ): SessionTransition = SessionTransition(
    clock = SessionClock(
      sessionId = clock.sessionId,
      expiresAtMs = nowMs + durationMs,
      activeElsewhere = activeElsewhere,
      probe = SessionProbeResult.Confirmed,
    ),
    context = context,
  )

  fun noteFailure(
    clock: SessionClock,
    context: PaymentContext,
    failure: SessionFailure,
  ): SessionTransition {
    val probe = if (!SessionBanner.hasSession(clock)) {
      SessionProbeResult.NotSignedIn
    } else {
      when (failure) {
        SessionFailure.Unauthorized -> SessionProbeResult.Rejected
        SessionFailure.Timeout, SessionFailure.Other -> SessionProbeResult.Unreachable
        is SessionFailure.Http ->
          if (failure.statusCode == 401 || failure.statusCode == 403) {
            SessionProbeResult.Rejected
          } else {
            SessionProbeResult.Unreachable
          }
      }
    }
    return SessionTransition(
      clock = SessionClock(
        sessionId = clock.sessionId,
        expiresAtMs = clock.expiresAtMs,
        activeElsewhere = clock.activeElsewhere,
        probe = probe,
      ),
      context = context,
    )
  }

  fun classify(error: Throwable): SessionFailure {
    if (error is MeridianError.HttpError) {
      return if (error.statusCode == 401 || error.statusCode == 403) {
        SessionFailure.Unauthorized
      } else {
        SessionFailure.Http(error.statusCode)
      }
    }
    val name = error.javaClass.simpleName.lowercase()
    val message = (error.message ?: "").lowercase()
    if (name.contains("timeout") || message.contains("timed out") || message.contains("timeout")) {
      return SessionFailure.Timeout
    }
    return SessionFailure.Other
  }
}
