package com.atlassian.meridian

import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetSocketAddress
import kotlin.math.abs

class SessionBannerTest {
  private val draft = InFlightPaymentDraft(
    recipientId = "northline-studio",
    amount = "18.50",
    reference = "Studio materials",
    method = PaymentMethod.card,
    reviewing = true,
    idempotencyKey = "pay-key-114",
  )

  @Test
  fun activeCopyStaysNonBlocking() {
    val active = SessionBanner.present(0, SessionBanner.EXPIRING_WINDOW_MS + 1, activeElsewhere = false)
    assertEquals(SessionBannerState.ACTIVE, active.state)
    assertEquals("Connected to secure payments platform", active.message)
    assertEquals(active.message, active.accessibilityLabel)
    assertFalse(active.blocksInteraction)
    assertNull(active.extendActionLabel)
    assertTrue(active.meetsWcagAa())
    assertTrue(active.minimumTapTargetDp >= 48)
  }

  @Test
  fun expiringSoonIncludesExtendActionAtFiveMinuteBoundary() {
    val now = 1_000L
    val expiring = SessionBanner.present(now, now + SessionBanner.EXPIRING_WINDOW_MS, activeElsewhere = false)
    assertEquals(SessionBannerState.EXPIRING_SOON, expiring.state)
    assertEquals("Session expiring soon. Tap to extend.", expiring.message)
    assertEquals("Tap to extend", expiring.extendActionLabel)
    assertFalse(expiring.blocksInteraction)
    assertEquals(SessionBanner.warningBackground, expiring.background)
    assertTrue(expiring.meetsWcagAa())
    assertTrue(expiring.contrastRatio() >= 4.5)
  }

  @Test
  fun justOutsideFiveMinutesStaysActive() {
    val now = 1_000L
    val active = SessionBanner.present(now, now + SessionBanner.EXPIRING_WINDOW_MS + 1, activeElsewhere = false)
    assertEquals(SessionBannerState.ACTIVE, active.state)
  }

  @Test
  fun activeElsewhereStaysNonBlocking() {
    val elsewhere = SessionBanner.present(0, SessionBanner.EXPIRING_WINDOW_MS + 60_000, activeElsewhere = true)
    assertEquals(SessionBannerState.ACTIVE_ELSEWHERE, elsewhere.state)
    assertEquals("Session active on another device.", elsewhere.message)
    assertEquals(elsewhere.message, elsewhere.accessibilityLabel)
    assertFalse(elsewhere.blocksInteraction)
    assertNull(elsewhere.extendActionLabel)
    assertTrue(elsewhere.meetsWcagAa())
  }

  @Test
  fun expiredBlocksAndUsesApprovedCopy() {
    val expired = SessionBanner.present(5_000, 5_000, activeElsewhere = true)
    assertEquals(SessionBannerState.EXPIRED, expired.state)
    assertEquals(
      "Session expired. Please re-authenticate to confirm this transfer.",
      expired.message,
    )
    assertTrue(expired.blocksInteraction)
    assertEquals("Re-authenticate", expired.reauthenticateActionLabel)
    assertNull(expired.extendActionLabel)
    assertTrue(expired.meetsWcagAa())
  }

  @Test
  fun extendKeepsInFlightDraftAndRenewsSession() {
    val extended = SessionRefresh.extend(50_000, draft = draft, activeElsewhere = false)
    assertEquals(draft, extended.draft)
    assertEquals(PaymentMethod.card, extended.draft.method)
    assertEquals("pay-key-114", extended.draft.idempotencyKey)
    assertEquals("18.50", extended.draft.amount)
    assertEquals("Studio materials", extended.draft.reference)
    assertTrue(extended.draft.reviewing)
    assertEquals(50_000 + SessionBanner.DEFAULT_DURATION_MS, extended.expiresAtMs)
    assertEquals(SessionBannerState.ACTIVE, extended.presentation.state)
    assertFalse(extended.presentation.blocksInteraction)
  }

  @Test
  fun extendDoesNotSwitchProviderBaseline() {
    val bank = draft.copy(method = PaymentMethod.bank)
    val extended = SessionRefresh.extend(1, draft = bank, activeElsewhere = false)
    assertEquals(PaymentMethod.bank, extended.draft.method)
    assertEquals("pay-key-114", extended.draft.idempotencyKey)
  }

  @Test
  fun uncertainRefreshRetainsExpiryKeyAndMethod() {
    val retained = SessionRefresh.retain(
      nowMs = 90_000,
      expiresAtMs = 150_000,
      activeElsewhere = false,
      draft = draft,
    )
    assertEquals(draft, retained.draft)
    assertEquals(PaymentMethod.card, retained.draft.method)
    assertEquals("pay-key-114", retained.draft.idempotencyKey)
    assertEquals(150_000, retained.expiresAtMs)
    assertEquals(SessionBannerState.EXPIRING_SOON, retained.presentation.state)
  }

  @Test
  fun reauthenticateKeepsTransferDraft() {
    val reauthed = SessionRefresh.reauthenticate(10_000, draft = draft)
    assertEquals(draft, reauthed.draft)
    assertFalse(reauthed.activeElsewhere)
    assertEquals(SessionBannerState.ACTIVE, reauthed.presentation.state)
    assertFalse(reauthed.presentation.blocksInteraction)
  }

  @Test
  fun contrastHelperMatchesBlackOnWhite() {
    val black = SessionColor("color.black", 0, 0, 0)
    val white = SessionColor("color.white", 255, 255, 255)
    val ratio = black.contrastRatio(white)
    assertTrue(abs(ratio - 21.0) < 0.001)
    val active = SessionBanner.present(0, SessionBanner.DEFAULT_DURATION_MS, activeElsewhere = false)
    assertTrue(active.contrastRatio() >= 4.5)
  }

  @Test
  fun refreshSessionKeepsSelectedRoom() {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    server.createContext("/api/v1/health") { exchange ->
      assertEquals("GET", exchange.requestMethod)
      assertEquals("room-pay-114", exchange.requestHeaders.getFirst("X-Rehearsal-Session"))
      val body = """{"status":"ok","service":"meridian","simulation":true}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, body.toByteArray().size.toLong())
      exchange.responseBody.write(body.toByteArray())
      exchange.close()
    }
    server.start()
    try {
      val health = runBlocking {
        MeridianClient("http://127.0.0.1:$port/api/v1", "room-pay-114").refreshSession()
      }
      assertEquals("ok", health.status)
      assertTrue(health.simulation)
    } finally {
      server.stop(0)
    }
  }
}
