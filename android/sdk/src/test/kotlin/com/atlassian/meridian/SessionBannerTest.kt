package com.atlassian.meridian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionBannerTest {
  private val now = 1_700_000_000_000L
  private val draft = PaymentDraft(
    recipientId = "northline-studio",
    amountText = "12.50",
    reference = "Studio deposit",
    method = PaymentMethod.card,
    reviewing = true,
    idempotencyKey = "pay-key-1",
  )

  @Test
  fun activeBannerHasNoAction() {
    val model = presentSession(sessionForPhase(SessionPhase.ACTIVE, now), now)
    assertEquals(SessionPhase.ACTIVE, model.phase)
    assertEquals(SessionBannerTone.SUCCESS, model.tone)
    assertEquals("Session active", model.title)
    assertNull(model.action)
    assertNull(model.clockLabel)
  }

  @Test
  fun expiringBannerShowsRemainingTimeAndRefresh() {
    val model = presentSession(sessionForPhase(SessionPhase.EXPIRING, now), now)
    assertEquals(SessionPhase.EXPIRING, model.phase)
    assertEquals(SessionBannerTone.WARNING, model.tone)
    assertEquals(SessionBannerAction.REFRESH, model.action)
    assertEquals("Refresh session", model.actionLabel)
    assertEquals(SessionTiming.previewExpiringSeconds, model.remainingSeconds)
    assertEquals("1:30", model.clockLabel)
    assertTrue(model.message.contains("1 minute 30 seconds remaining"))
    assertTrue(model.accessibilityLabel.contains("Session expiring"))
  }

  @Test
  fun thresholdBoundaries() {
    val atThreshold = presentSession(
      CustomerSession.Active(now + SessionTiming.expiringThresholdSeconds * 1000L),
      now,
    )
    assertEquals(SessionPhase.EXPIRING, atThreshold.phase)
    assertEquals("2:00", atThreshold.clockLabel)

    val outside = presentSession(
      CustomerSession.Active(now + (SessionTiming.expiringThresholdSeconds + 1) * 1000L),
      now,
    )
    assertEquals(SessionPhase.ACTIVE, outside.phase)

    val oneSecond = presentSession(CustomerSession.Active(now + 1000L), now)
    assertEquals(1, oneSecond.remainingSeconds)
    assertEquals("0:01", oneSecond.clockLabel)
    assertTrue(oneSecond.message.startsWith("1 second remaining"))
  }

  @Test
  fun elapsedActiveSessionPresentsAsExpired() {
    val derived = presentSession(CustomerSession.Active(now), now)
    val explicit = presentSession(CustomerSession.Expired, now)
    assertEquals(SessionPhase.EXPIRED, derived.phase)
    assertEquals(SessionBannerTone.DANGER, derived.tone)
    assertEquals(SessionBannerAction.SIGN_IN, derived.action)
    assertEquals(explicit.title, derived.title)
    assertEquals(explicit.message, derived.message)
    assertTrue(derived.message.contains("Entered payment details are still here"))
  }

  @Test
  fun activeElsewhereSignedOutAndUnknownAreDistinct() {
    val elsewhere = presentSession(CustomerSession.ActiveElsewhere("   "), now)
    assertEquals(SessionPhase.ACTIVE_ELSEWHERE, elsewhere.phase)
    assertEquals(SessionBannerTone.INFORMATION, elsewhere.tone)
    assertEquals(SessionBannerAction.CONTINUE_HERE, elsewhere.action)
    assertTrue(elsewhere.message.contains("another device"))

    val named = presentSession(CustomerSession.ActiveElsewhere("Meridian web"), now)
    assertTrue(named.message.contains("Meridian web"))

    val signedOut = presentSession(CustomerSession.SignedOut, now)
    assertEquals(SessionPhase.SIGNED_OUT, signedOut.phase)
    assertEquals(SessionBannerTone.NEUTRAL, signedOut.tone)
    assertEquals(SessionBannerAction.SIGN_IN, signedOut.action)
    assertTrue(signedOut.message.contains("amount, recipient and reference"))

    val unknown = presentSession(CustomerSession.Unknown, now)
    assertEquals(SessionPhase.UNKNOWN, unknown.phase)
    assertEquals(SessionBannerTone.ATTENTION, unknown.tone)
    assertEquals(SessionBannerAction.TRY_AGAIN, unknown.action)
    assertTrue(unknown.message.contains("payment details stay on this screen"))
  }

  @Test
  fun everyPhaseHasADistinctTitleAndTone() {
    val models = SessionPhase.entries.map { presentSession(sessionForPhase(it, now), now) }
    assertEquals(6, models.map { it.title }.toSet().size)
    assertEquals(6, models.map { it.tone }.toSet().size)
  }

  @Test
  fun remainingPhrases() {
    assertEquals("0 seconds", formatRemaining(0))
    assertEquals("2 seconds", formatRemaining(2))
    assertEquals("1 minute", formatRemaining(60))
    assertEquals("1 minute 1 second", formatRemaining(61))
    assertEquals("2 minutes", formatRemaining(120))
  }

  @Test
  fun refreshKeepsTheSamePaymentDraft() {
    val session = sessionForPhase(SessionPhase.EXPIRING, now)
    val updated = applySessionAction(session, SessionBannerAction.REFRESH, now, true, draft)
    assertSame(draft, updated.payment)
    assertEquals(CustomerSession.Active(now + SessionTiming.lengthSeconds * 1000L), updated.session)
    assertTrue(updated.announcement.contains("unchanged"))
  }

  @Test
  fun failedRefreshKeepsSessionAndDraft() {
    val session = CustomerSession.Active(now + 45_000L)
    val updated = applySessionAction(session, SessionBannerAction.REFRESH, now, false, draft)
    assertSame(draft, updated.payment)
    assertEquals(session, updated.session)
    assertTrue(updated.announcement.contains("still here"))
  }

  @Test
  fun recoveryActionsDoNotReplacePaymentDraft() {
    val signedIn = applySessionAction(CustomerSession.Expired, SessionBannerAction.SIGN_IN, now, false, draft)
    assertSame(draft, signedIn.payment)
    assertTrue(signedIn.session is CustomerSession.Active)

    val continued = applySessionAction(
      CustomerSession.ActiveElsewhere("Meridian web"),
      SessionBannerAction.CONTINUE_HERE,
      now,
      false,
      draft,
    )
    assertSame(draft, continued.payment)

    val offline = applySessionAction(CustomerSession.Unknown, SessionBannerAction.TRY_AGAIN, now, false, draft)
    assertSame(draft, offline.payment)
    assertEquals(CustomerSession.Unknown, offline.session)
    assertTrue(offline.announcement.contains("still here"))

    val online = applySessionAction(CustomerSession.Unknown, SessionBannerAction.TRY_AGAIN, now, true, draft)
    assertSame(draft, online.payment)
    assertTrue(online.session is CustomerSession.Active)
  }
}
