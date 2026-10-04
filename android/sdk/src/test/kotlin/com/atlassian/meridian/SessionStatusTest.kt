package com.atlassian.meridian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionStatusTest {
  private val now = 1_700_000_000_000L

  @Test
  fun testFiveMinutesRemainingStaysActive() {
    val expires = now + SESSION_WARNING_WINDOW_MS
    assertEquals(
      SessionPhase.Banner(SessionBannerState.ACTIVE),
      sessionPhase(SessionPresence.HERE, expires, now),
    )
    assertFalse(sessionRequiresReauthentication(SessionPresence.HERE, expires, now))
  }

  @Test
  fun testUnderFiveMinutesIsNonBlockingWarning() {
    val expires = now + SESSION_WARNING_WINDOW_MS - 1
    assertEquals(
      SessionPhase.Banner(SessionBannerState.EXPIRING_SOON),
      sessionPhase(SessionPresence.HERE, expires, now),
    )
    assertFalse(sessionRequiresReauthentication(SessionPresence.HERE, expires, now))
    val copy = sessionBannerCopy(SessionBannerState.EXPIRING_SOON, 4 * 60 * 1000)
    assertEquals(SESSION_EXPIRING_MESSAGE, copy.message)
    assertEquals("Session expiring soon. Tap to extend. 4 minutes remaining.", copy.accessibilityLabel)
    assertEquals("warning", copy.indicator)
    val palette = sessionBannerPalette(SessionBannerState.EXPIRING_SOON)
    assertEquals("color.background.warning", palette.backgroundToken)
    assertEquals("color.text.warning", palette.foregroundToken)
    assertEquals("#FFF5DB", palette.backgroundHex)
    assertEquals("#9E4C00", palette.foregroundHex)
  }

  @Test
  fun testCompleteExpiryRequiresReauthenticationOnly() {
    assertTrue(sessionRequiresReauthentication(SessionPresence.HERE, now, now))
    assertTrue(sessionRequiresReauthentication(SessionPresence.HERE, now - 1, now))
    assertTrue(sessionRequiresReauthentication(SessionPresence.ELSEWHERE, now, now))
    assertFalse(sessionRequiresReauthentication(SessionPresence.SIGNED_OUT, now - 60_000, now))
    assertEquals(
      SessionPhase.Banner(SessionBannerState.SIGNED_OUT),
      sessionPhase(SessionPresence.SIGNED_OUT, now - 60_000, now),
    )
  }

  @Test
  fun testActiveElsewhereAndSignedOutCopy() {
    val later = now + 10 * 60 * 1000
    assertEquals(
      SessionPhase.Banner(SessionBannerState.ACTIVE_ELSEWHERE),
      sessionPhase(SessionPresence.ELSEWHERE, later, now),
    )
    assertEquals(
      SessionPhase.Banner(SessionBannerState.EXPIRING_SOON),
      sessionPhase(SessionPresence.ELSEWHERE, now + 60_000, now),
    )
    assertEquals("Session active.", sessionBannerCopy(SessionBannerState.ACTIVE).message)
    assertEquals("check", sessionBannerCopy(SessionBannerState.ACTIVE).indicator)
    assertEquals(
      "Session active on another device.",
      sessionBannerCopy(SessionBannerState.ACTIVE_ELSEWHERE).message,
    )
    assertEquals("devices", sessionBannerCopy(SessionBannerState.ACTIVE_ELSEWHERE).indicator)
    assertEquals("Signed out.", sessionBannerCopy(SessionBannerState.SIGNED_OUT).message)
    assertEquals("signed-out", sessionBannerCopy(SessionBannerState.SIGNED_OUT).indicator)
  }

  @Test
  fun testRefreshKeepsPaymentDraft() {
    val draft = PaymentFormDraft(
      recipientId = "northline-studio",
      amount = "18.25",
      reference = "Studio rent",
      method = PaymentMethod.bank,
      reviewing = true,
      idempotencyKey = "pay-key-171",
    )
    val refreshed = refreshSessionInPlace(
      draft,
      PaymentSessionClock(SessionPresence.ELSEWHERE, now + 30_000),
      now,
    )
    assertEquals(draft, refreshed.draft)
    assertEquals(SessionPresence.HERE, refreshed.session.presence)
    assertEquals(now + PAYMENT_SESSION_TTL_MS, refreshed.session.expiresAtEpochMs)
    assertEquals(
      SessionPhase.Banner(SessionBannerState.ACTIVE),
      sessionPhase(refreshed.session.presence, refreshed.session.expiresAtEpochMs, now),
    )
  }

  @Test
  fun testBannerContrastMeetsWcagAa() {
    val warning = contrastRatio("#9E4C00", "#FFF5DB")
    assertTrue(warning >= 4.5)
    assertTrue(warning < 6.0)
    SessionBannerState.values().forEach { state ->
      val palette = sessionBannerPalette(state)
      val ratio = contrastRatio(palette.foregroundHex, palette.backgroundHex)
      assertTrue("$state contrast $ratio", ratio >= 4.5)
    }
  }
}
