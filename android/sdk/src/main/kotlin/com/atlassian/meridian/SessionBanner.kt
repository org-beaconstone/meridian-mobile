package com.atlassian.meridian

/**
 * Rehearsal sign-in timing. This is not a production authenticator.
 */
object SessionTiming {
  const val lengthSeconds = 600
  const val expiringThresholdSeconds = 120
  const val previewExpiringSeconds = 90
}

enum class SessionPhase(val label: String) {
  ACTIVE("Active"),
  EXPIRING("Expiring"),
  ACTIVE_ELSEWHERE("Active elsewhere"),
  SIGNED_OUT("Signed out"),
  EXPIRED("Expired"),
  UNKNOWN("Unknown"),
}

enum class SessionBannerTone {
  SUCCESS,
  WARNING,
  INFORMATION,
  NEUTRAL,
  DANGER,
  ATTENTION,
}

enum class SessionBannerAction(val label: String) {
  REFRESH("Refresh session"),
  SIGN_IN("Sign in"),
  CONTINUE_HERE("Continue here"),
  TRY_AGAIN("Try again"),
}

/**
 * Customer rehearsal session. Distinct from the X-Rehearsal-Session room id.
 */
sealed class CustomerSession {
  data class Active(val expiresAtEpochMs: Long) : CustomerSession()
  data class ActiveElsewhere(val deviceName: String) : CustomerSession()
  data object SignedOut : CustomerSession()
  data object Expired : CustomerSession()
  data object Unknown : CustomerSession()
}

/** Payment fields the banner must leave untouched. */
data class PaymentDraft(
  val recipientId: String,
  val amountText: String,
  val reference: String,
  val method: PaymentMethod,
  val reviewing: Boolean,
  val idempotencyKey: String,
)

data class SessionBannerModel(
  val phase: SessionPhase,
  val tone: SessionBannerTone,
  val title: String,
  val message: String,
  val clockLabel: String?,
  val remainingSeconds: Int?,
  val action: SessionBannerAction?,
  val actionLabel: String?,
  val accessibilityLabel: String,
)

data class SessionUpdate(
  val session: CustomerSession,
  val announcement: String,
  val payment: PaymentDraft,
)

fun formatRemaining(totalSeconds: Int): String {
  val seconds = maxOf(0, totalSeconds)
  val minutes = seconds / 60
  val rest = seconds % 60
  val parts = mutableListOf<String>()
  if (minutes > 0) {
    parts.add("$minutes ${if (minutes == 1) "minute" else "minutes"}")
  }
  if (rest > 0 || minutes == 0) {
    parts.add("$rest ${if (rest == 1) "second" else "seconds"}")
  }
  return parts.joinToString(" ")
}

fun formatClock(totalSeconds: Int): String {
  val seconds = maxOf(0, totalSeconds)
  val minutes = seconds / 60
  val rest = seconds % 60
  return "%d:%02d".format(minutes, rest)
}

fun sessionForPhase(
  phase: SessionPhase,
  nowEpochMs: Long,
  deviceName: String = "Meridian web",
): CustomerSession = when (phase) {
  SessionPhase.ACTIVE ->
    CustomerSession.Active(nowEpochMs + SessionTiming.lengthSeconds * 1000L)
  SessionPhase.EXPIRING ->
    CustomerSession.Active(nowEpochMs + SessionTiming.previewExpiringSeconds * 1000L)
  SessionPhase.ACTIVE_ELSEWHERE -> CustomerSession.ActiveElsewhere(deviceName)
  SessionPhase.SIGNED_OUT -> CustomerSession.SignedOut
  SessionPhase.EXPIRED -> CustomerSession.Expired
  SessionPhase.UNKNOWN -> CustomerSession.Unknown
}

fun presentSession(session: CustomerSession, nowEpochMs: Long): SessionBannerModel = when (session) {
  is CustomerSession.Active -> {
    val remaining = remainingWholeSeconds(session.expiresAtEpochMs, nowEpochMs)
    when {
      remaining <= 0 -> expiredBanner()
      remaining <= SessionTiming.expiringThresholdSeconds -> expiringBanner(remaining)
      else -> activeBanner()
    }
  }
  is CustomerSession.ActiveElsewhere -> elsewhereBanner(session.deviceName)
  CustomerSession.SignedOut -> signedOutBanner()
  CustomerSession.Expired -> expiredBanner()
  CustomerSession.Unknown -> unknownBanner()
}

fun applySessionAction(
  session: CustomerSession,
  action: SessionBannerAction,
  nowEpochMs: Long,
  apiReachable: Boolean,
  payment: PaymentDraft,
): SessionUpdate = when (action) {
  SessionBannerAction.REFRESH ->
    if (apiReachable) {
      SessionUpdate(
        CustomerSession.Active(nowEpochMs + SessionTiming.lengthSeconds * 1000L),
        "Session refreshed. Payment details are unchanged.",
        payment,
      )
    } else {
      SessionUpdate(
        session,
        "Couldn't refresh the session. Your payment details are still here.",
        payment,
      )
    }
  SessionBannerAction.SIGN_IN ->
    SessionUpdate(
      CustomerSession.Active(nowEpochMs + SessionTiming.lengthSeconds * 1000L),
      "Signed in on this device. Payment details are unchanged.",
      payment,
    )
  SessionBannerAction.CONTINUE_HERE ->
    SessionUpdate(
      CustomerSession.Active(nowEpochMs + SessionTiming.lengthSeconds * 1000L),
      "Continuing on this device. Payment details are unchanged.",
      payment,
    )
  SessionBannerAction.TRY_AGAIN ->
    if (apiReachable) {
      SessionUpdate(
        CustomerSession.Active(nowEpochMs + SessionTiming.lengthSeconds * 1000L),
        "Session confirmed. Payment details are unchanged.",
        payment,
      )
    } else {
      SessionUpdate(
        CustomerSession.Unknown,
        "We still couldn't confirm this session. Your payment details are still here.",
        payment,
      )
    }
}

private fun remainingWholeSeconds(expiresAtEpochMs: Long, nowEpochMs: Long): Int {
  val delta = expiresAtEpochMs - nowEpochMs
  if (delta <= 0L) return 0
  return (delta / 1000L).toInt()
}

private fun model(
  phase: SessionPhase,
  tone: SessionBannerTone,
  title: String,
  message: String,
  clockLabel: String? = null,
  remainingSeconds: Int? = null,
  action: SessionBannerAction? = null,
) = SessionBannerModel(
  phase = phase,
  tone = tone,
  title = title,
  message = message,
  clockLabel = clockLabel,
  remainingSeconds = remainingSeconds,
  action = action,
  actionLabel = action?.label,
  accessibilityLabel = "$title. $message",
)

private fun activeBanner() = model(
  SessionPhase.ACTIVE,
  SessionBannerTone.SUCCESS,
  "Session active",
  "Signed in on this device. You can keep entering this payment.",
)

private fun expiringBanner(remaining: Int): SessionBannerModel {
  val spoken = formatRemaining(remaining)
  return model(
    SessionPhase.EXPIRING,
    SessionBannerTone.WARNING,
    "Session expiring",
    "$spoken remaining. Refresh to stay signed in. This payment stays on screen.",
    formatClock(remaining),
    remaining,
    SessionBannerAction.REFRESH,
  )
}

private fun elsewhereBanner(deviceName: String) = model(
  SessionPhase.ACTIVE_ELSEWHERE,
  SessionBannerTone.INFORMATION,
  "Active on another device",
  "Signed in on ${displayDevice(deviceName)}. Continue here when you are ready. Entered payment details stay on this screen.",
  action = SessionBannerAction.CONTINUE_HERE,
)

private fun signedOutBanner() = model(
  SessionPhase.SIGNED_OUT,
  SessionBannerTone.NEUTRAL,
  "Signed out",
  "Sign in again to send this payment. The amount, recipient and reference you entered are kept.",
  action = SessionBannerAction.SIGN_IN,
)

private fun expiredBanner() = model(
  SessionPhase.EXPIRED,
  SessionBannerTone.DANGER,
  "Session expired",
  "Your sign-in has expired. Sign in again to continue. Entered payment details are still here.",
  action = SessionBannerAction.SIGN_IN,
)

private fun unknownBanner() = model(
  SessionPhase.UNKNOWN,
  SessionBannerTone.ATTENTION,
  "Session unknown",
  "We couldn't confirm this session. Try again when you are ready. Your payment details stay on this screen.",
  action = SessionBannerAction.TRY_AGAIN,
)

private fun displayDevice(name: String): String {
  val trimmed = name.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
  if (trimmed.isEmpty()) return "another device"
  return if (trimmed.length <= 40) trimmed else trimmed.substring(0, 40)
}
