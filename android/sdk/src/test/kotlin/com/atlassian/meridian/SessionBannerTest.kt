package com.atlassian.meridian

import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetSocketAddress
import java.net.SocketTimeoutException

class SessionBannerTest {
  private val now = 1_000_000L
  private val window = SessionBanner.expiringWindowMs
  private val draft = PaymentContext(
    recipientId = "northline-studio",
    amount = "12.50",
    reference = "Studio books",
    method = PaymentMethod.bank,
    reviewing = true,
    idempotencyKey = "pay-key-136",
  )
  private val cardDraft = PaymentContext(
    recipientId = "birch-bloom",
    amount = "4.00",
    reference = "Coffee",
    method = PaymentMethod.card,
    reviewing = false,
    idempotencyKey = "card-key",
  )

  @Test
  fun activeSessionIsQuietAndDistinct() {
    val active = SessionBanner.present(
      now,
      SessionClock(sessionId = "room-a", expiresAtMs = now + window + 1, probe = SessionProbeResult.Confirmed),
    )
    assertEquals(SessionVisualState.Active, active.state)
    assertEquals("Session active", active.title)
    assertEquals("You're securely signed in.", active.message)
    assertNull(active.actionLabel)
    assertFalse(active.blocksPaymentEntry)
    assertTrue(active.meetsWcagAa())
  }

  @Test
  fun expiringSessionShowsRemainingTimeAndRefresh() {
    val expiring = SessionBanner.present(
      now,
      SessionClock(sessionId = "room-a", expiresAtMs = now + (4 * 60 + 12) * 1000, probe = SessionProbeResult.Confirmed),
    )
    assertEquals(SessionVisualState.Expiring, expiring.state)
    assertEquals("Your session expires in 4 min 12 sec.", expiring.message)
    assertEquals("Refresh", expiring.actionLabel)
    assertEquals("Refresh session", expiring.actionAccessibilityLabel)
    assertTrue(expiring.accessibilityLabel.contains("4 min 12 sec"))
    assertFalse(expiring.blocksPaymentEntry)
    assertTrue(expiring.meetsWcagAa())

    val boundary = SessionBanner.present(
      now,
      SessionClock(sessionId = "room-a", expiresAtMs = now + window, probe = SessionProbeResult.Confirmed),
    )
    val outside = SessionBanner.present(
      now,
      SessionClock(sessionId = "room-a", expiresAtMs = now + window + 1, probe = SessionProbeResult.Confirmed),
    )
    assertEquals(SessionVisualState.Expiring, boundary.state)
    assertTrue(boundary.message.contains("5 min"))
    assertEquals(SessionVisualState.Active, outside.state)
  }

  @Test
  fun activeElsewhereIsItsOwnState() {
    val elsewhere = SessionBanner.present(
      now,
      SessionClock(
        sessionId = "room-a",
        expiresAtMs = now + window + 5_000,
        activeElsewhere = true,
        probe = SessionProbeResult.Confirmed,
      ),
    )
    val soon = SessionBanner.present(
      now,
      SessionClock(
        sessionId = "room-a",
        expiresAtMs = now + 60_000,
        activeElsewhere = true,
        probe = SessionProbeResult.Confirmed,
      ),
    )
    assertEquals(SessionVisualState.ActiveElsewhere, elsewhere.state)
    assertEquals("This session is active on another device.", elsewhere.message)
    assertEquals(SessionVisualState.ActiveElsewhere, soon.state)
    assertTrue(soon.message.contains("another device"))
    assertTrue(soon.message.contains("1 min"))
    assertTrue(elsewhere.meetsWcagAa())
    assertTrue(soon.meetsWcagAa())
  }

  @Test
  fun signedOutKeepsThePaymentDraft() {
    val signedOut = SessionBanner.present(now, SessionClock())
    val rejected = SessionBanner.present(
      now,
      SessionClock(sessionId = "room-a", expiresAtMs = now + window + 1, probe = SessionProbeResult.Rejected),
    )
    assertEquals(SessionVisualState.SignedOut, signedOut.state)
    assertEquals("You've been signed out. Sign in to continue.", signedOut.message)
    assertEquals(SessionVisualState.SignedOut, rejected.state)
    assertEquals("Sign in", rejected.actionLabel)
    assertFalse(signedOut.blocksPaymentEntry)
    assertFalse(rejected.blocksPaymentEntry)

    val signedIn = SessionActions.signIn(now, "room-a", draft)
    assertEquals(draft, signedIn.context)
    assertEquals(draft.idempotencyKey, signedIn.idempotencyKey)
    assertEquals(PaymentMethod.bank, signedIn.method)
    assertEquals(ProviderId.worldpay, signedIn.provider)
    assertEquals(SessionVisualState.Active, SessionBanner.resolve(now, signedIn.clock))
  }

  @Test
  fun unknownAndExpiredRecoveryDoesNotDropContext() {
    val expired = SessionBanner.present(
      now,
      SessionClock(sessionId = "room-a", expiresAtMs = now, probe = SessionProbeResult.Confirmed),
    )
    val past = SessionBanner.present(
      now,
      SessionClock(sessionId = "room-a", expiresAtMs = now - 1, probe = SessionProbeResult.Confirmed),
    )
    val unknown = SessionBanner.present(
      now,
      SessionClock(sessionId = "room-a", expiresAtMs = now - 1, probe = SessionProbeResult.Unreachable),
    )
    assertEquals(SessionVisualState.Expired, expired.state)
    assertEquals(SessionVisualState.Expired, past.state)
    assertTrue(expired.message.contains("still here"))
    assertEquals("Refresh", expired.actionLabel)
    assertEquals(SessionVisualState.Unknown, unknown.state)
    assertTrue(unknown.message.contains("still here"))
    assertEquals("Try again", unknown.actionLabel)
    assertFalse(expired.blocksPaymentEntry)
    assertFalse(unknown.blocksPaymentEntry)
    assertTrue(expired.meetsWcagAa())
    assertTrue(unknown.meetsWcagAa())

    val clock = SessionClock(sessionId = "room-a", expiresAtMs = 500, probe = SessionProbeResult.Confirmed)
    val timedOut = SessionActions.noteFailure(clock, draft, SessionFailure.Timeout)
    assertEquals(draft, timedOut.context)
    assertEquals("room-a", timedOut.clock.sessionId)
    assertEquals(500L, timedOut.clock.expiresAtMs)
    assertEquals(ProviderId.worldpay, timedOut.provider)
    assertEquals(SessionVisualState.Unknown, SessionBanner.resolve(10_000, timedOut.clock))

    val cardTimeout = SessionActions.noteFailure(clock, cardDraft, SessionActions.classify(SocketTimeoutException("Read timed out")))
    assertEquals(ProviderId.adyen, cardTimeout.provider)
    assertEquals(PaymentMethod.card, cardTimeout.method)
    assertEquals(SessionProbeResult.Unreachable, cardTimeout.clock.probe)

    val unauthorized = SessionActions.noteFailure(clock, draft, SessionFailure.Unauthorized)
    assertEquals(SessionProbeResult.Rejected, unauthorized.clock.probe)
    assertEquals(draft.idempotencyKey, unauthorized.idempotencyKey)
    assertEquals(
      SessionProbeResult.Rejected,
      SessionActions.noteFailure(clock, draft, SessionFailure.Http(403)).clock.probe,
    )
    assertEquals(
      SessionProbeResult.Unreachable,
      SessionActions.noteFailure(clock, draft, SessionFailure.Http(503)).clock.probe,
    )

    val extended = SessionActions.refresh(now, clock, draft, activeElsewhere = true)
    assertEquals(draft, extended.context)
    assertEquals("room-a", extended.clock.sessionId)
    assertEquals(now + SessionBanner.defaultDurationMs, extended.clock.expiresAtMs)
    assertTrue(extended.clock.activeElsewhere)
    assertEquals(SessionProbeResult.Confirmed, extended.clock.probe)
    assertEquals(ProviderId.worldpay, extended.provider)
  }

  @Test
  fun visualsAndTextScale() {
    val states = listOf(
      SessionClock(sessionId = "room-a", expiresAtMs = now + window + 1, probe = SessionProbeResult.Confirmed),
      SessionClock(sessionId = "room-a", expiresAtMs = now + 60_000, probe = SessionProbeResult.Confirmed),
      SessionClock(sessionId = "room-a", expiresAtMs = now + window + 1, activeElsewhere = true, probe = SessionProbeResult.Confirmed),
      SessionClock(),
      SessionClock(sessionId = "room-a", expiresAtMs = now, probe = SessionProbeResult.Confirmed),
      SessionClock(sessionId = "room-a", expiresAtMs = now + window, probe = SessionProbeResult.Unreachable),
    ).map { SessionBanner.present(now, it) }
    assertEquals(6, states.map { it.background.token }.toSet().size)
    assertEquals(6, states.map { "${it.background.red},${it.background.green},${it.background.blue}" }.toSet().size)
    val large = SessionTextScale(2.0)
    val base = SessionTextScale(1.0)
    val compact = SessionTextScale(0.8)
    assertTrue(large.bodyPoints > base.bodyPoints)
    assertTrue(large.titlePoints > base.titlePoints)
    assertTrue(base.tapTargetPoints >= 48)
    assertTrue(large.tapTargetPoints >= 48)
    assertTrue(compact.tapTargetPoints >= 48)
    assertTrue(large.wraps)
    assertTrue(states.all { it.meetsWcagAa(large) })

    val order = SessionAccessibility.focusOrder(showsAction = true)
    assertEquals(SessionAccessibility.banner, order.first())
    assertEquals(SessionAccessibility.action, order[1])
    assertEquals(SessionAccessibility.paymentForm, order.last())
    assertTrue(order.indexOf(SessionAccessibility.banner) < order.indexOf(SessionAccessibility.paymentForm))
    val quiet = SessionAccessibility.focusOrder(showsAction = false)
    assertEquals(SessionAccessibility.banner, quiet.first())
    assertFalse(quiet.contains(SessionAccessibility.action))
  }

  @Test
  fun remainingTimeFormatting() {
    assertEquals("4 min 12 sec", SessionBanner.formatRemaining(252_000))
    assertEquals("5 min", SessionBanner.formatRemaining(300_000))
    assertEquals("45 sec", SessionBanner.formatRemaining(45_000))
    assertEquals("1 sec", SessionBanner.formatRemaining(1))
  }

  @Test
  fun refreshSessionUsesTheSelectedRoomAndDoesNotStartAPayment() {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    val paths = mutableListOf<String>()
    server.createContext("/api/v1/health") { exchange ->
      paths += "${exchange.requestMethod} ${exchange.requestURI.path}"
      val session = exchange.requestHeaders.getFirst("X-Rehearsal-Session")
      val idempotency = exchange.requestHeaders.getFirst("Idempotency-Key")
      assertEquals("room-136", session)
      assertNull(idempotency)
      val body = """{"status":"ok","service":"meridian","simulation":true}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.responseHeaders.add("X-Meridian-Session-Elsewhere", "true")
      exchange.sendResponseHeaders(200, body.toByteArray().size.toLong())
      exchange.responseBody.write(body.toByteArray())
      exchange.close()
    }
    server.createContext("/api/v1/payments") { exchange ->
      paths += "UNEXPECTED ${exchange.requestURI.path}"
      exchange.sendResponseHeaders(500, -1)
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient("http://127.0.0.1:${server.address.port}/api/v1", "room-136")
      val payload = runBlocking { client.refreshSession() }
      assertTrue(payload.healthy)
      assertTrue(payload.activeElsewhere)
      assertEquals(listOf("GET /api/v1/health"), paths)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun healthFailureDoesNotOpenAnotherProviderCall() {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    var hits = 0
    server.createContext("/api/v1/health") { exchange ->
      hits += 1
      val body = """{"error":"no"}"""
      exchange.sendResponseHeaders(401, body.toByteArray().size.toLong())
      exchange.responseBody.write(body.toByteArray())
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient("http://127.0.0.1:${server.address.port}/api/v1", "room-136")
      val error = runBlocking {
        try {
          client.refreshSession()
          null
        } catch (error: MeridianError.HttpError) {
          error
        }
      }
      assertEquals(401, error?.statusCode)
      assertEquals(1, hits)
    } finally {
      server.stop(0)
    }
  }
}
