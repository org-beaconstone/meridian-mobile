package com.atlassian.meridian

import java.util.Locale

/**
 * Corridor-aware session banner for the Android payment screen.
 *
 * There is no separate authentication Activity. The Android equivalent of the
 * auth/session screen is [com.atlassian.meridian.MeridianClient]'s rehearsal
 * session on the payment screen (`X-Rehearsal-Session`). This model only reads
 * that session. It does not perform a new auth check and it does not call a
 * payment provider.
 *
 * Dismissal is remembered per session state. A later phase or corridor change
 * shows the banner again. Lookup failure is never dismissible and never
 * claims the customer is signed in or signed out.
 */

/** Existing account-card and brand colours from the payment screen. */
object AccountCardTokens {
  const val BACKGROUND: Long = 0x142C35
  const val TEXT: Long = 0xFFFFFF
  const val GOLD: Long = 0xD5B77A
}

object SessionBannerCopy {
  const val ACTIVE = "You're securely signed in"
  const val EXPIRING = "Your session ends soon"
  const val SIGNED_OUT_CORE = "We signed you out"
  const val SIGNED_OUT_DEVICE = "on another device"
  const val SIGNED_OUT = "We signed you out on another device"
  const val LOOKUP_FAILED = "We couldn't confirm your session. Try again"
  const val CORRIDOR_EUROPEAN = "New: payments now supported in your European corridor"
  const val CHECKING = "Checking your session"
  const val DISMISSED = "Session banner dismissed"
}

data class CorridorNotice(
  val id: String,
  val message: String,
) {
  companion object {
    val europeanLaunch = CorridorNotice(
      id = "european-launch",
      message = SessionBannerCopy.CORRIDOR_EUROPEAN,
    )
  }
}

/** Phases the current session record can already report. Not an auth request. */
enum class SessionPhase {
  active,
  expiring,
  signedOutElsewhere,
}

enum class SessionLookup {
  Idle,
  Resolving,
  Ready,
  Failed,
}

enum class SnapshotKind {
  empty,
  resolving,
  active,
  expiring,
  signedOutElsewhere,
  lookupFailed,
  corridorNotice,
}

data class SessionSnapshot(
  val kind: SnapshotKind,
  val sessionId: String? = null,
  val deviceDetail: String? = null,
  val corridorNotice: CorridorNotice? = null,
)

enum class BannerTone {
  active,
  expiring,
  signedOutElsewhere,
  lookupFailed,
  corridor,
}

sealed class SessionBannerPresentation {
  abstract val liveIdentity: String

  data object Hidden : SessionBannerPresentation() {
    override val liveIdentity: String = "hidden"
  }

  data object Skeleton : SessionBannerPresentation() {
    override val liveIdentity: String = "resolving"
    const val announcement: String = SessionBannerCopy.CHECKING
  }

  data class Visible(
    val dismissalKey: String,
    val metricState: String,
    val coreMessage: String,
    val detail: String?,
    val announcement: String,
    val dismissible: Boolean,
    val tone: BannerTone,
  ) : SessionBannerPresentation() {
    override val liveIdentity: String = dismissalKey
  }
}

/**
 * Maps the payment screen's existing session lifecycle into a banner snapshot.
 *
 * [knownPhase] is honoured only after the current session read has succeeded.
 * A failed read always becomes lookup-failed, including when a corridor notice
 * is also present.
 */
fun paymentSessionSnapshot(
  clientConnected: Boolean,
  lookup: SessionLookup,
  sessionId: String?,
  sessionConfirmed: Boolean,
  corridorNotice: CorridorNotice? = null,
  corridorResolving: Boolean = false,
  knownPhase: SessionPhase? = null,
  deviceDetail: String? = null,
): SessionSnapshot {
  val id = sessionId?.takeIf { it.isNotBlank() }
  if (lookup == SessionLookup.Failed) {
    return SessionSnapshot(kind = SnapshotKind.lookupFailed, sessionId = id)
  }
  if (lookup == SessionLookup.Resolving || (clientConnected && lookup == SessionLookup.Idle) || corridorResolving) {
    return SessionSnapshot(kind = SnapshotKind.resolving, sessionId = id, corridorNotice = corridorNotice)
  }
  if (sessionConfirmed && lookup == SessionLookup.Ready) {
    val kind = when (knownPhase) {
      SessionPhase.expiring -> SnapshotKind.expiring
      SessionPhase.signedOutElsewhere -> SnapshotKind.signedOutElsewhere
      SessionPhase.active, null -> SnapshotKind.active
    }
    return SessionSnapshot(
      kind = kind,
      sessionId = id,
      deviceDetail = deviceDetail,
      corridorNotice = corridorNotice,
    )
  }
  if (corridorNotice != null) {
    return SessionSnapshot(kind = SnapshotKind.corridorNotice, sessionId = id, corridorNotice = corridorNotice)
  }
  return SessionSnapshot(kind = SnapshotKind.empty, sessionId = id)
}

fun resolveSessionBanner(
  snapshot: SessionSnapshot,
  dismissedKeys: Set<String>,
): SessionBannerPresentation {
  if (snapshot.kind == SnapshotKind.resolving) return SessionBannerPresentation.Skeleton
  if (snapshot.kind == SnapshotKind.empty) return SessionBannerPresentation.Hidden

  val built = visibleContent(snapshot)
  if (built.dismissible && dismissedKeys.contains(built.dismissalKey)) return SessionBannerPresentation.Hidden
  return built
}

/**
 * Fits session and corridor messaging on one line. Corridor or device detail
 * is shortened before the core state message.
 */
fun fitBannerLine(core: String, detail: String?, maxChars: Int): String {
  val budget = maxChars.coerceAtLeast(1)
  val coreText = core.trim()
  val detailText = detail?.trim().orEmpty()
  if (detailText.isEmpty()) return ellipsize(coreText, budget)
  if (coreText.isEmpty()) return ellipsize(detailText, budget)
  val combined = "$coreText $detailText"
  if (combined.length <= budget) return combined
  val roomForDetail = budget - coreText.length - 1
  if (roomForDetail >= 2) {
    return "$coreText ${ellipsize(detailText, roomForDetail)}"
  }
  return ellipsize(coreText, budget)
}

data class BannerDismissalRate(
  val state: String,
  val impressions: Int,
  val dismissals: Int,
  val rate: Double,
) {
  fun logLine(): String = dismissalRateLogLine(state, impressions, dismissals, rate)
}

fun dismissalRateLogLine(state: String, impressions: Int, dismissals: Int, rate: Double): String =
  "banner_dismissal_rate state=$state impressions=$impressions dismissals=$dismissals rate=" +
    String.format(Locale.US, "%.4f", rate)

/** Counts banner dismissal rate by state for observability. */
class SessionBannerMetrics {
  private val impressions = linkedMapOf<String, Int>()
  private val dismissals = linkedMapOf<String, Int>()

  fun recordImpression(state: String) {
    impressions[state] = (impressions[state] ?: 0) + 1
  }

  fun recordDismissal(state: String): BannerDismissalRate {
    dismissals[state] = (dismissals[state] ?: 0) + 1
    return rateFor(state)
  }

  fun rateFor(state: String): BannerDismissalRate {
    val shown = impressions[state] ?: 0
    val closed = dismissals[state] ?: 0
    val rate = if (shown == 0) 0.0 else closed.toDouble() / shown.toDouble()
    return BannerDismissalRate(state, shown, closed, rate)
  }

  fun ratesByState(): Map<String, BannerDismissalRate> {
    val states = LinkedHashSet<String>()
    states.addAll(impressions.keys)
    states.addAll(dismissals.keys)
    return states.associateWith { rateFor(it) }
  }
}

data class BannerPalette(val background: Long, val text: Long)

object SessionBannerTokens {
  val active = themed(lightBg = 0xE4EEF1, lightText = AccountCardTokens.BACKGROUND, darkBg = AccountCardTokens.BACKGROUND, darkText = AccountCardTokens.TEXT)
  val expiring = themed(lightBg = 0xF8E8C8, lightText = 0x3E2A00, darkBg = 0x3A2C14, darkText = 0xF8E8C8)
  val signedOutElsewhere = themed(lightBg = 0xF8DCD7, lightText = 0x5A1C14, darkBg = 0x3F221C, darkText = 0xF8DCD7)
  val lookupFailed = themed(lightBg = 0xE6EBE4, lightText = AccountCardTokens.BACKGROUND, darkBg = 0x1A2C33, darkText = 0xE4EEF1)
  val corridor = themed(lightBg = 0xF4EBD6, lightText = AccountCardTokens.BACKGROUND, darkBg = AccountCardTokens.BACKGROUND, darkText = AccountCardTokens.GOLD)
  const val SKELETON_LIGHT: Long = 0xD9E2E6
  const val SKELETON_DARK: Long = 0x243840

  fun forTone(tone: BannerTone): Pair<BannerPalette, BannerPalette> = when (tone) {
    BannerTone.active -> active
    BannerTone.expiring -> expiring
    BannerTone.signedOutElsewhere -> signedOutElsewhere
    BannerTone.lookupFailed -> lookupFailed
    BannerTone.corridor -> corridor
  }

  private fun themed(lightBg: Long, lightText: Long, darkBg: Long, darkText: Long) =
    BannerPalette(lightBg, lightText) to BannerPalette(darkBg, darkText)
}

fun contrastRatio(background: Long, foreground: Long): Double {
  val lighter = maxOf(relativeLuminance(background), relativeLuminance(foreground))
  val darker = minOf(relativeLuminance(background), relativeLuminance(foreground))
  return (lighter + 0.05) / (darker + 0.05)
}

private fun visibleContent(snapshot: SessionSnapshot): SessionBannerPresentation.Visible {
  val corridor = snapshot.corridorNotice
  val device = snapshot.deviceDetail?.takeIf { it.isNotBlank() } ?: SessionBannerCopy.SIGNED_OUT_DEVICE
  return when (snapshot.kind) {
    SnapshotKind.active -> line(
      snapshot = snapshot,
      metric = "active",
      core = SessionBannerCopy.ACTIVE,
      detail = corridor?.message,
      tone = BannerTone.active,
      dismissible = true,
      corridorId = corridor?.id,
    )
    SnapshotKind.expiring -> line(
      snapshot = snapshot,
      metric = "expiring",
      core = SessionBannerCopy.EXPIRING,
      detail = corridor?.message,
      tone = BannerTone.expiring,
      dismissible = true,
      corridorId = corridor?.id,
    )
    SnapshotKind.signedOutElsewhere -> line(
      snapshot = snapshot,
      metric = "signed_out_elsewhere",
      core = SessionBannerCopy.SIGNED_OUT_CORE,
      detail = if (corridor == null) device else "$device. ${corridor.message}",
      tone = BannerTone.signedOutElsewhere,
      dismissible = true,
      corridorId = corridor?.id,
      deviceKey = device,
    )
    SnapshotKind.lookupFailed -> line(
      snapshot = snapshot,
      metric = "lookup_failed",
      core = SessionBannerCopy.LOOKUP_FAILED,
      detail = null,
      tone = BannerTone.lookupFailed,
      dismissible = false,
      corridorId = null,
    )
    SnapshotKind.corridorNotice -> line(
      snapshot = snapshot,
      metric = "corridor_notice",
      core = corridor?.message ?: SessionBannerCopy.CORRIDOR_EUROPEAN,
      detail = null,
      tone = BannerTone.corridor,
      dismissible = true,
      corridorId = corridor?.id,
    )
    SnapshotKind.empty, SnapshotKind.resolving -> error("No visible banner for ${snapshot.kind}")
  }
}

private fun line(
  snapshot: SessionSnapshot,
  metric: String,
  core: String,
  detail: String?,
  tone: BannerTone,
  dismissible: Boolean,
  corridorId: String?,
  deviceKey: String? = null,
): SessionBannerPresentation.Visible {
  val announcement = fitBannerLine(core, detail, Int.MAX_VALUE)
  val key = listOf(snapshot.sessionId.orEmpty(), metric, corridorId.orEmpty(), deviceKey.orEmpty()).joinToString("|")
  return SessionBannerPresentation.Visible(
    dismissalKey = key,
    metricState = metric,
    coreMessage = core,
    detail = detail,
    announcement = announcement,
    dismissible = dismissible,
    tone = tone,
  )
}

private fun ellipsize(text: String, budget: Int): String {
  if (text.length <= budget) return text
  if (budget == 1) return "…"
  return text.take(budget - 1).trimEnd() + "…"
}

private fun relativeLuminance(rgb: Long): Double {
  val red = ((rgb shr 16) and 0xFF) / 255.0
  val green = ((rgb shr 8) and 0xFF) / 255.0
  val blue = (rgb and 0xFF) / 255.0
  return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
}

private fun linearize(channel: Double): Double =
  if (channel <= 0.04045) channel / 12.92 else Math.pow((channel + 0.055) / 1.055, 2.4)
