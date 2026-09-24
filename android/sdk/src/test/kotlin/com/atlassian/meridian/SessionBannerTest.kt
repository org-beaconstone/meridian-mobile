package com.atlassian.meridian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionBannerTest {
  @Test
  fun firstInstallWithNoSessionAndNoCorridorShowsNothing() {
    val snapshot = paymentSessionSnapshot(
      clientConnected = false,
      lookup = SessionLookup.Idle,
      sessionId = null,
      sessionConfirmed = false,
    )
    assertEquals(SessionBannerPresentation.Hidden, resolveSessionBanner(snapshot, emptySet()))
  }

  @Test
  fun resolvingSessionShowsSkeletonRatherThanAState() {
    val snapshot = paymentSessionSnapshot(
      clientConnected = true,
      lookup = SessionLookup.Resolving,
      sessionId = "meridian-rehearsal",
      sessionConfirmed = false,
      corridorNotice = CorridorNotice.europeanLaunch,
      corridorResolving = true,
    )
    assertEquals(SessionBannerPresentation.Skeleton, resolveSessionBanner(snapshot, emptySet()))
  }

  @Test
  fun rendersDesignSpecCopyForEachState() {
    assertEquals(SessionBannerCopy.ACTIVE, visible(active()).coreMessage)
    assertEquals(SessionBannerCopy.EXPIRING, visible(phase(SessionPhase.expiring)).coreMessage)
    assertEquals(
      SessionBannerCopy.SIGNED_OUT,
      visible(phase(SessionPhase.signedOutElsewhere)).announcement,
    )
    assertEquals(SessionBannerCopy.LOOKUP_FAILED, visible(failed()).coreMessage)
    assertEquals(
      SessionBannerCopy.CORRIDOR_EUROPEAN,
      visible(corridorOnly()).announcement,
    )
  }

  @Test
  fun lookupFailedIsNotDismissibleAndOtherStatesAre() {
    assertFalse(visible(failed()).dismissible)
    assertTrue(visible(active()).dismissible)
    assertTrue(visible(phase(SessionPhase.expiring)).dismissible)
    assertTrue(visible(phase(SessionPhase.signedOutElsewhere)).dismissible)
    assertTrue(visible(corridorOnly()).dismissible)

    val failedBanner = visible(failed())
    val stillVisible = resolveSessionBanner(failed(), setOf(failedBanner.dismissalKey))
    assertEquals(failedBanner, stillVisible)
  }

  @Test
  fun dismissalClearsOnlyTheCurrentState() {
    val activeBanner = visible(active())
    val expiring = phase(SessionPhase.expiring)
    val dismissed = setOf(activeBanner.dismissalKey)

    assertEquals(SessionBannerPresentation.Hidden, resolveSessionBanner(active(), dismissed))
    val next = visible(expiring, dismissed)
    assertEquals(SessionBannerCopy.EXPIRING, next.coreMessage)
    assertEquals(SessionBannerPresentation.Hidden, resolveSessionBanner(active(), dismissed))
  }

  @Test
  fun corridorChangeShowsTheBannerAgain() {
    val withEuropean = active(CorridorNotice.europeanLaunch)
    val dismissed = setOf(visible(withEuropean).dismissalKey)
    assertEquals(SessionBannerPresentation.Hidden, resolveSessionBanner(withEuropean, dismissed))

    val nextCorridor = CorridorNotice(id = "sepa-reminder", message = "Payments in your European corridor")
    val again = visible(active(nextCorridor), dismissed)
    assertEquals(SessionBannerCopy.ACTIVE, again.coreMessage)
    assertEquals(nextCorridor.message, again.detail)
  }

  @Test
  fun sessionIdChangeShowsADismissedStateAgain() {
    val first = paymentSessionSnapshot(true, SessionLookup.Ready, "room-a", true)
    val dismissed = setOf(visible(first).dismissalKey)
    val second = paymentSessionSnapshot(true, SessionLookup.Ready, "room-b", true)
    assertEquals(SessionBannerCopy.ACTIVE, visible(second, dismissed).coreMessage)
  }

  @Test
  fun lookupFailureDoesNotAssertSignedInOrCorridor() {
    val snapshot = paymentSessionSnapshot(
      clientConnected = true,
      lookup = SessionLookup.Failed,
      sessionId = "meridian-rehearsal",
      sessionConfirmed = true,
      corridorNotice = CorridorNotice.europeanLaunch,
      knownPhase = SessionPhase.active,
    )
    val banner = visible(snapshot)
    assertEquals(BannerTone.lookupFailed, banner.tone)
    assertEquals(SessionBannerCopy.LOOKUP_FAILED, banner.announcement)
    assertFalse(banner.announcement.contains("European"))
  }

  @Test
  fun corridorNoticeCanShowWithoutAPriorSession() {
    val snapshot = paymentSessionSnapshot(
      clientConnected = false,
      lookup = SessionLookup.Idle,
      sessionId = null,
      sessionConfirmed = false,
      corridorNotice = CorridorNotice.europeanLaunch,
    )
    assertEquals(SessionBannerCopy.CORRIDOR_EUROPEAN, visible(snapshot).announcement)
  }

  @Test
  fun truncatesCorridorAndDeviceDetailBeforeTheCoreMessage() {
    val activeLine = fitBannerLine(
      SessionBannerCopy.ACTIVE,
      SessionBannerCopy.CORRIDOR_EUROPEAN,
      maxChars = 28,
    )
    assertTrue(activeLine.startsWith(SessionBannerCopy.ACTIVE))
    assertTrue(activeLine.endsWith("…"))
    assertFalse(activeLine.contains(SessionBannerCopy.CORRIDOR_EUROPEAN))

    val deviceLine = fitBannerLine(
      SessionBannerCopy.SIGNED_OUT_CORE,
      SessionBannerCopy.SIGNED_OUT_DEVICE,
      maxChars = 20,
    )
    assertTrue(deviceLine.startsWith(SessionBannerCopy.SIGNED_OUT_CORE))
    assertTrue(deviceLine.endsWith("…"))

    assertEquals(
      SessionBannerCopy.SIGNED_OUT,
      fitBannerLine(SessionBannerCopy.SIGNED_OUT_CORE, SessionBannerCopy.SIGNED_OUT_DEVICE, 80),
    )
    assertEquals(
      "${SessionBannerCopy.ACTIVE} ${SessionBannerCopy.CORRIDOR_EUROPEAN}",
      visible(active(CorridorNotice.europeanLaunch)).announcement,
    )
  }

  @Test
  fun dismissalRateIsLoggedByState() {
    val metrics = SessionBannerMetrics()
    metrics.recordImpression("active")
    metrics.recordImpression("active")
    metrics.recordImpression("expiring")
    val activeRate = metrics.recordDismissal("active")
    val expiringRate = metrics.recordDismissal("expiring")

    assertEquals(0.5, activeRate.rate, 0.0001)
    assertEquals(1.0, expiringRate.rate, 0.0001)
    assertEquals(
      "banner_dismissal_rate state=active impressions=2 dismissals=1 rate=0.5000",
      activeRate.logLine(),
    )
    assertEquals(
      "banner_dismissal_rate state=expiring impressions=1 dismissals=1 rate=1.0000",
      expiringRate.logLine(),
    )
    assertEquals(0.0, metrics.rateFor("lookup_failed").rate, 0.0)
  }

  @Test
  fun lightAndDarkTokenPairsMeetWcagAa() {
    val tones = listOf(
      SessionBannerTokens.active,
      SessionBannerTokens.expiring,
      SessionBannerTokens.signedOutElsewhere,
      SessionBannerTokens.lookupFailed,
      SessionBannerTokens.corridor,
    )
    tones.forEach { (light, dark) ->
      assertTrue(contrastRatio(light.background, light.text) >= 4.5)
      assertTrue(contrastRatio(dark.background, dark.text) >= 4.5)
    }
    val (lightActive, darkActive) = SessionBannerTokens.active
    assertEquals(AccountCardTokens.BACKGROUND, lightActive.text)
    assertEquals(AccountCardTokens.BACKGROUND, darkActive.background)
    assertEquals(AccountCardTokens.TEXT, darkActive.text)
    val corridorDark = SessionBannerTokens.corridor.second
    assertEquals(AccountCardTokens.BACKGROUND, corridorDark.background)
    assertEquals(AccountCardTokens.GOLD, corridorDark.text)
  }

  private fun active(corridor: CorridorNotice? = null) = paymentSessionSnapshot(
    clientConnected = true,
    lookup = SessionLookup.Ready,
    sessionId = "meridian-rehearsal",
    sessionConfirmed = true,
    corridorNotice = corridor,
  )

  private fun phase(phase: SessionPhase) = paymentSessionSnapshot(
    clientConnected = true,
    lookup = SessionLookup.Ready,
    sessionId = "meridian-rehearsal",
    sessionConfirmed = true,
    knownPhase = phase,
  )

  private fun failed() = paymentSessionSnapshot(
    clientConnected = true,
    lookup = SessionLookup.Failed,
    sessionId = "meridian-rehearsal",
    sessionConfirmed = true,
  )

  private fun corridorOnly() = paymentSessionSnapshot(
    clientConnected = false,
    lookup = SessionLookup.Idle,
    sessionId = null,
    sessionConfirmed = false,
    corridorNotice = CorridorNotice.europeanLaunch,
  )

  private fun visible(
    snapshot: SessionSnapshot,
    dismissed: Set<String> = emptySet(),
  ): SessionBannerPresentation.Visible {
    val presentation = resolveSessionBanner(snapshot, dismissed)
    assertTrue(presentation is SessionBannerPresentation.Visible)
    return presentation as SessionBannerPresentation.Visible
  }
}
