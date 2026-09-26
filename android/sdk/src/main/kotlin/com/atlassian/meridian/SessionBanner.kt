package com.atlassian.meridian

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withTimeout
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

const val SESSION_CHECK_TIMEOUT_MS = 4_000L
const val SESSION_EXPIRING_WINDOW_MS = 120_000L
const val SESSION_LABEL_MAX_CHARS = 24
const val WCAG_AA_CONTRAST = 4.5

val SESSION_ID_PATTERN = Regex("[A-Za-z0-9_-]{3,64}")

enum class AuthSessionPhase {
  RESOLVING,
  ACTIVE,
  EXPIRING,
  ACTIVE_ELSEWHERE,
  SIGNED_OUT,
  UNCONFIRMED,
}

data class AuthSession(
  val phase: AuthSessionPhase,
  val accountName: String? = null,
  val deviceName: String? = null,
) {
  companion object {
    fun resolving() = AuthSession(AuthSessionPhase.RESOLVING)
  }
}

data class SessionSnapshot(
  val sessionState: String? = null,
  val accountName: String? = null,
  val deviceName: String? = null,
  val expiresAtEpochMs: Long? = null,
)

data class SessionBanner(
  val phase: AuthSessionPhase,
  val showSkeleton: Boolean,
  val minimal: Boolean,
  val blocking: Boolean,
  val title: String,
  val body: String,
  val actionLabel: String?,
  val announcement: String,
  val backgroundArgb: Long,
  val foregroundArgb: Long,
)

object AuthScreenTags {
  const val BANNER = "session-banner"
  const val BANNER_STATUS = "session-banner-status"
  const val BANNER_ACTION = "session-banner-action"
  const val API_BASE_URL = "api-base-url"
  const val ROOM = "rehearsal-room"
  const val CONNECT = "connect"
  const val PAYMENT = "payment-content"
}

private const val EXPIRING_BG = 0xFFFFF6DE
private const val EXPIRING_FG = 0xFF3A2500
private const val SIGNED_OUT_BG = 0xFFFDECEA
private const val SIGNED_OUT_FG = 0xFF5C1010
private const val ELSEWHERE_BG = 0xFFE7F3F7
private const val ELSEWHERE_FG = 0xFF082E3C
private const val NEUTRAL_BG = 0xFFF3F5F3
private const val NEUTRAL_FG = 0xFF1B2A24
private const val ACTIVE_BG = 0xFFF4F7F5
private const val ACTIVE_FG = 0xFF1E3A2F

private val KNOWN_SESSION_TOKENS = setOf(
  "active",
  "healthy",
  "expiring",
  "expiring_soon",
  "active_elsewhere",
  "elsewhere",
  "signed_out",
  "expired",
)

/**
 * Blank session is signed out. A malformed id cannot be confirmed.
 * A well-formed id returns null so the caller probes the existing session.
 */
fun classifySessionId(sessionId: String): AuthSession? {
  if (sessionId.isBlank()) return AuthSession(AuthSessionPhase.SIGNED_OUT)
  if (!SESSION_ID_PATTERN.matches(sessionId)) return AuthSession(AuthSessionPhase.UNCONFIRMED)
  return null
}

fun normalizeSessionToken(raw: String?): String? =
  raw?.trim()?.lowercase()?.replace('-', '_')?.replace(' ', '_')?.takeIf { it.isNotEmpty() }

fun interpretSessionSnapshot(
  snapshot: SessionSnapshot,
  nowEpochMs: Long,
  expiringWindowMs: Long = SESSION_EXPIRING_WINDOW_MS,
): AuthSession {
  val token = normalizeSessionToken(snapshot.sessionState)
  val expiresAt = snapshot.expiresAtEpochMs
  val expired = expiresAt != null && expiresAt <= nowEpochMs
  val expiringSoon = expiresAt != null && !expired && expiresAt - nowEpochMs <= expiringWindowMs
  if (token == "signed_out" || token == "expired" || expired) {
    return AuthSession(AuthSessionPhase.SIGNED_OUT)
  }
  if (expiringSoon || token == "expiring" || token == "expiring_soon") {
    return AuthSession(AuthSessionPhase.EXPIRING)
  }
  if (token == "active_elsewhere" || token == "elsewhere") {
    return AuthSession(
      AuthSessionPhase.ACTIVE_ELSEWHERE,
      accountName = snapshot.accountName,
      deviceName = snapshot.deviceName,
    )
  }
  if (token != null && token !in KNOWN_SESSION_TOKENS) {
    return AuthSession(AuthSessionPhase.UNCONFIRMED)
  }
  return AuthSession(AuthSessionPhase.ACTIVE)
}

/**
 * Probe the session the caller already selected. Timeouts and unrecognized
 * failures stay unconfirmed. Only an explicit auth rejection is signed out.
 */
suspend fun resolveAuthSession(
  sessionId: String,
  timeoutMs: Long = SESSION_CHECK_TIMEOUT_MS,
  nowEpochMs: Long = System.currentTimeMillis(),
  expiringWindowMs: Long = SESSION_EXPIRING_WINDOW_MS,
  probe: suspend () -> SessionSnapshot,
): AuthSession {
  classifySessionId(sessionId)?.let { return it }
  return try {
    val snapshot = withTimeout(timeoutMs) { probe() }
    interpretSessionSnapshot(snapshot, nowEpochMs, expiringWindowMs)
  } catch (timeout: TimeoutCancellationException) {
    AuthSession(AuthSessionPhase.UNCONFIRMED)
  } catch (cancelled: CancellationException) {
    throw cancelled
  } catch (http: MeridianError.HttpError) {
    if (http.statusCode == 401 || http.statusCode == 403) AuthSession(AuthSessionPhase.SIGNED_OUT)
    else AuthSession(AuthSessionPhase.UNCONFIRMED)
  } catch (_: Exception) {
    AuthSession(AuthSessionPhase.UNCONFIRMED)
  }
}

fun sanitizeLabel(raw: String): String =
  raw.replace(Regex("[\\u0000-\\u001F\\u007F]+"), " ")
    .replace(Regex("\\s+"), " ")
    .trim()

fun truncateLabel(raw: String, maxChars: Int = SESSION_LABEL_MAX_CHARS): String {
  val clean = sanitizeLabel(raw)
  if (clean.length <= maxChars) return clean
  val head = clean.take((maxChars - 1).coerceAtLeast(1)).trimEnd()
  return "$head…"
}

fun elsewhereMessage(accountName: String?, deviceName: String?): String {
  val device = deviceName?.let(::sanitizeLabel)?.takeIf { it.isNotEmpty() }?.let(::truncateLabel)
  val account = accountName?.let(::sanitizeLabel)?.takeIf { it.isNotEmpty() }?.let(::truncateLabel)
  return when {
    device != null && account != null -> "Signed in on $device for $account."
    device != null -> "Signed in on $device."
    account != null -> "Signed in for $account on another device."
    else -> "This account is also signed in on another device."
  }
}

fun presentSessionBanner(session: AuthSession): SessionBanner {
  return when (session.phase) {
    AuthSessionPhase.RESOLVING -> SessionBanner(
      phase = session.phase,
      showSkeleton = true,
      minimal = false,
      blocking = false,
      title = "",
      body = "",
      actionLabel = null,
      announcement = "Checking session",
      backgroundArgb = NEUTRAL_BG,
      foregroundArgb = NEUTRAL_FG,
    )
    AuthSessionPhase.ACTIVE -> SessionBanner(
      phase = session.phase,
      showSkeleton = false,
      minimal = true,
      blocking = false,
      title = "Signed in",
      body = "",
      actionLabel = null,
      announcement = "Signed in",
      backgroundArgb = ACTIVE_BG,
      foregroundArgb = ACTIVE_FG,
    )
    AuthSessionPhase.EXPIRING -> {
      val body = "Your session is about to expire. Sign in again to continue."
      SessionBanner(
        phase = session.phase,
        showSkeleton = false,
        minimal = false,
        blocking = false,
        title = "Session expiring",
        body = body,
        actionLabel = "Sign in again",
        announcement = "Session expiring. $body",
        backgroundArgb = EXPIRING_BG,
        foregroundArgb = EXPIRING_FG,
      )
    }
    AuthSessionPhase.SIGNED_OUT -> {
      val body = "You've been signed out. Sign in to continue."
      SessionBanner(
        phase = session.phase,
        showSkeleton = false,
        minimal = false,
        blocking = true,
        title = "Signed out",
        body = body,
        actionLabel = "Sign in",
        announcement = "Signed out. $body",
        backgroundArgb = SIGNED_OUT_BG,
        foregroundArgb = SIGNED_OUT_FG,
      )
    }
    AuthSessionPhase.ACTIVE_ELSEWHERE -> {
      val body = elsewhereMessage(session.accountName, session.deviceName)
      SessionBanner(
        phase = session.phase,
        showSkeleton = false,
        minimal = false,
        blocking = false,
        title = "Signed in elsewhere",
        body = body,
        actionLabel = null,
        announcement = "Signed in elsewhere. $body",
        backgroundArgb = ELSEWHERE_BG,
        foregroundArgb = ELSEWHERE_FG,
      )
    }
    AuthSessionPhase.UNCONFIRMED -> {
      val body = "We couldn't confirm your session. You can continue."
      SessionBanner(
        phase = session.phase,
        showSkeleton = false,
        minimal = false,
        blocking = false,
        title = "Session status unavailable",
        body = body,
        actionLabel = "Try again",
        announcement = "Session status unavailable. $body",
        backgroundArgb = NEUTRAL_BG,
        foregroundArgb = NEUTRAL_FG,
      )
    }
  }
}

fun paymentContentAvailable(banner: SessionBanner, hasAccountState: Boolean): Boolean =
  hasAccountState && !banner.blocking && !banner.showSkeleton

fun authScreenFocusOrder(banner: SessionBanner, paymentAvailable: Boolean): List<String> {
  val order = mutableListOf(AuthScreenTags.BANNER, AuthScreenTags.BANNER_STATUS)
  if (banner.actionLabel != null) order += AuthScreenTags.BANNER_ACTION
  order += AuthScreenTags.API_BASE_URL
  order += AuthScreenTags.ROOM
  order += AuthScreenTags.CONNECT
  if (paymentAvailable) order += AuthScreenTags.PAYMENT
  return order
}

fun contrastRatio(foregroundArgb: Long, backgroundArgb: Long): Double {
  fun channel(value: Long, shift: Int): Double {
    val s = ((value shr shift) and 0xFF).toDouble() / 255.0
    return if (s <= 0.04045) s / 12.92 else ((s + 0.055) / 1.055).pow(2.4)
  }
  fun luminance(value: Long): Double =
    0.2126 * channel(value, 16) + 0.7152 * channel(value, 8) + 0.0722 * channel(value, 0)
  val lighter = max(luminance(foregroundArgb), luminance(backgroundArgb))
  val darker = min(luminance(foregroundArgb), luminance(backgroundArgb))
  return (lighter + 0.05) / (darker + 0.05)
}

fun meetsWcagAa(foregroundArgb: Long, backgroundArgb: Long): Boolean =
  contrastRatio(foregroundArgb, backgroundArgb) >= WCAG_AA_CONTRAST

class SessionRefreshGuard {
  private var generation = 0

  fun next(): Int {
    generation += 1
    return generation
  }

  fun isCurrent(token: Int): Boolean = token == generation
}

class SessionBannerState(initial: AuthSession = AuthSession.resolving()) {
  var session: AuthSession = initial
    private set
  var banner: SessionBanner = presentSessionBanner(initial)
    private set
  private val announcementLog = mutableListOf(banner.announcement)
  val announcements: List<String> get() = announcementLog

  fun apply(next: AuthSession) {
    session = next
    banner = presentSessionBanner(next)
    if (announcementLog.last() != banner.announcement) announcementLog += banner.announcement
  }
}
