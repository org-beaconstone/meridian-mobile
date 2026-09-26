package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.net.InetSocketAddress

class SessionBannerUiTest {
  private val mapper = ObjectMapper().registerKotlinModule()

  @Test
  fun bannerTransitionsAcrossSessionStates() = runBlocking {
    val ui = SessionBannerState()
    assertTrue(ui.banner.showSkeleton)
    assertFalse(ui.banner.blocking)
    assertEquals("", ui.banner.title)
    assertEquals("", ui.banner.body)
    assertEquals("Checking session", ui.banner.announcement)
    assertNull(ui.banner.actionLabel)
    assertFalse(paymentContentAvailable(ui.banner, hasAccountState = true))

    ui.apply(interpretSessionSnapshot(SessionSnapshot(), nowEpochMs = 1_000))
    assertEquals(AuthSessionPhase.ACTIVE, ui.session.phase)
    assertTrue(ui.banner.minimal)
    assertFalse(ui.banner.blocking)
    assertEquals("Signed in", ui.banner.title)
    assertFalse(ui.banner.body.contains("expire", ignoreCase = true))
    assertTrue(paymentContentAvailable(ui.banner, hasAccountState = true))

    ui.apply(interpretSessionSnapshot(SessionSnapshot(sessionState = "expiring"), nowEpochMs = 1_000))
    assertEquals(AuthSessionPhase.EXPIRING, ui.session.phase)
    assertEquals("Session expiring", ui.banner.title)
    assertEquals("Your session is about to expire. Sign in again to continue.", ui.banner.body)
    assertEquals("Sign in again", ui.banner.actionLabel)
    assertFalse(ui.banner.blocking)
    assertTrue(paymentContentAvailable(ui.banner, hasAccountState = true))

    val longAccount = "Northline Studio Customer Account With A Very Long Legal Name"
    val longDevice = "Pixel-9-Pro-Fold-Shared-Family-Tablet-In-The-Kitchen"
    ui.apply(
      interpretSessionSnapshot(
        SessionSnapshot(
          sessionState = "active elsewhere",
          accountName = longAccount,
          deviceName = "\n$longDevice\t",
        ),
        nowEpochMs = 1_000,
      )
    )
    assertEquals(AuthSessionPhase.ACTIVE_ELSEWHERE, ui.session.phase)
    assertEquals("Signed in elsewhere", ui.banner.title)
    assertFalse(ui.banner.blocking)
    assertNull(ui.banner.actionLabel)
    assertFalse(ui.banner.body.contains(longAccount))
    assertFalse(ui.banner.body.contains(longDevice))
    assertFalse(ui.banner.body.contains("\n"))
    assertTrue(ui.banner.body.contains("…"))
    assertTrue(ui.banner.body.length <= 80)
    assertTrue(paymentContentAvailable(ui.banner, hasAccountState = true))

    ui.apply(interpretSessionSnapshot(SessionSnapshot(sessionState = "expired"), nowEpochMs = 1_000))
    assertEquals(AuthSessionPhase.SIGNED_OUT, ui.session.phase)
    assertEquals("You've been signed out. Sign in to continue.", ui.banner.body)
    assertEquals("Sign in", ui.banner.actionLabel)
    assertTrue(ui.banner.blocking)
    assertFalse(paymentContentAvailable(ui.banner, hasAccountState = true))

    ui.apply(resolveAuthSession("meridian-rehearsal", timeoutMs = 40) {
      delay(2_000)
      SessionSnapshot()
    })
    assertEquals(AuthSessionPhase.UNCONFIRMED, ui.session.phase)
    assertFalse(ui.banner.blocking)
    assertEquals("We couldn't confirm your session. You can continue.", ui.banner.body)
    assertFalse(ui.banner.title.contains("signed out", ignoreCase = true))
    assertFalse(ui.banner.body.contains("signed out", ignoreCase = true))
    assertFalse(ui.banner.body.contains("expire", ignoreCase = true))
    assertEquals("Try again", ui.banner.actionLabel)
    assertTrue(paymentContentAvailable(ui.banner, hasAccountState = true))

    assertEquals(
      listOf(
        "Checking session",
        "Signed in",
        "Session expiring. Your session is about to expire. Sign in again to continue.",
        ui.announcements[3],
        "Signed out. You've been signed out. Sign in to continue.",
        "Session status unavailable. We couldn't confirm your session. You can continue.",
      ),
      ui.announcements,
    )
    assertEquals(ui.announcements.distinct().size, ui.announcements.size)
    assertTrue(ui.announcements[3].startsWith("Signed in elsewhere."))
  }

  @Test
  fun eachStateMeetsWcagAaContrast() {
    val phases = listOf(
      AuthSession.resolving(),
      AuthSession(AuthSessionPhase.ACTIVE),
      AuthSession(AuthSessionPhase.EXPIRING),
      AuthSession(AuthSessionPhase.SIGNED_OUT),
      AuthSession(AuthSessionPhase.ACTIVE_ELSEWHERE, accountName = "Ada", deviceName = "Phone"),
      AuthSession(AuthSessionPhase.UNCONFIRMED),
    )
    phases.forEach { session ->
      val banner = presentSessionBanner(session)
      assertTrue(
        "${session.phase} contrast ${contrastRatio(banner.foregroundArgb, banner.backgroundArgb)}",
        meetsWcagAa(banner.foregroundArgb, banner.backgroundArgb),
      )
    }
    val blackOnWhite = contrastRatio(0xFF000000, 0xFFFFFFFF)
    assertTrue(blackOnWhite > 20)
    assertEquals(1.0, contrastRatio(0xFFFFFFFF, 0xFFFFFFFF), 0.01)
  }

  @Test
  fun focusOrderPutsBannerBeforeAuthFields() {
    AuthSessionPhase.values().forEach { phase ->
      val banner = presentSessionBanner(
        AuthSession(phase, accountName = "Ada", deviceName = "Phone")
      )
      val withPayment = authScreenFocusOrder(banner, paymentAvailable = true)
      val withoutPayment = authScreenFocusOrder(banner, paymentAvailable = false)
      assertTrue(withPayment.indexOf(AuthScreenTags.BANNER) == 0)
      assertTrue(withPayment.indexOf(AuthScreenTags.BANNER_STATUS) < withPayment.indexOf(AuthScreenTags.API_BASE_URL))
      assertTrue(withPayment.indexOf(AuthScreenTags.API_BASE_URL) < withPayment.indexOf(AuthScreenTags.ROOM))
      assertTrue(withPayment.indexOf(AuthScreenTags.ROOM) < withPayment.indexOf(AuthScreenTags.CONNECT))
      if (banner.actionLabel != null) {
        assertTrue(withPayment.indexOf(AuthScreenTags.BANNER_ACTION) < withPayment.indexOf(AuthScreenTags.API_BASE_URL))
      } else {
        assertFalse(withPayment.contains(AuthScreenTags.BANNER_ACTION))
      }
      if (banner.blocking || banner.showSkeleton) {
        assertFalse(paymentContentAvailable(banner, hasAccountState = true))
        assertFalse(withoutPayment.contains(AuthScreenTags.PAYMENT))
      } else {
        assertTrue(withPayment.last() == AuthScreenTags.PAYMENT)
      }
    }
  }

  @Test
  fun truncationKeepsShortNamesAndBoundsLongOnes() {
    assertEquals("Kitchen tablet", truncateLabel("Kitchen tablet"))
    assertEquals(24, truncateLabel("1234567890123456789012345").length)
    assertTrue(truncateLabel("1234567890123456789012345").endsWith("…"))
    val exact = "A".repeat(SESSION_LABEL_MAX_CHARS)
    assertEquals(exact, truncateLabel(exact))
    val message = elsewhereMessage("  Ada\nLovelace  ", "  Desk phone  ")
    assertEquals("Signed in on Desk phone for Ada Lovelace.", message)
    assertEquals("This account is also signed in on another device.", elsewhereMessage("  ", null))
  }

  @Test
  fun expiryClockBlocksOnlyWhenGenuinelyExpired() {
    val now = 1_700_000_000_000L
    val soon = interpretSessionSnapshot(
      SessionSnapshot(sessionState = "active", expiresAtEpochMs = now + 60_000),
      nowEpochMs = now,
    )
    assertEquals(AuthSessionPhase.EXPIRING, soon.phase)
    assertFalse(presentSessionBanner(soon).blocking)

    val later = interpretSessionSnapshot(
      SessionSnapshot(sessionState = "active", expiresAtEpochMs = now + SESSION_EXPIRING_WINDOW_MS + 1),
      nowEpochMs = now,
    )
    assertEquals(AuthSessionPhase.ACTIVE, later.phase)

    val past = interpretSessionSnapshot(
      SessionSnapshot(sessionState = "active_elsewhere", expiresAtEpochMs = now, accountName = "Ada"),
      nowEpochMs = now,
    )
    assertEquals(AuthSessionPhase.SIGNED_OUT, past.phase)
    assertTrue(presentSessionBanner(past).blocking)

    val explicit = interpretSessionSnapshot(
      SessionSnapshot(sessionState = "signed_out", expiresAtEpochMs = now + 3_600_000),
      nowEpochMs = now,
    )
    assertEquals(AuthSessionPhase.SIGNED_OUT, explicit.phase)
  }

  @Test
  fun elsewhereYieldsToExpiringAndUnknownTokensStayNeutral() {
    val now = 50_000L
    val both = interpretSessionSnapshot(
      SessionSnapshot(
        sessionState = "elsewhere",
        expiresAtEpochMs = now + 10_000,
        deviceName = "Work phone",
      ),
      nowEpochMs = now,
    )
    assertEquals(AuthSessionPhase.EXPIRING, both.phase)

    val corridor = interpretSessionSnapshot(
      SessionSnapshot(sessionState = "eu_launch", accountName = "Europe notice"),
      nowEpochMs = now,
    )
    assertEquals(AuthSessionPhase.UNCONFIRMED, corridor.phase)
    val banner = presentSessionBanner(corridor)
    assertFalse(banner.body.contains("eu_launch"))
    assertFalse(banner.body.contains("Europe"))
    assertFalse(banner.blocking)
  }

  @Test
  fun failedChecksDoNotAssertSignedOut() = runBlocking {
    var called = false
    val blank = resolveAuthSession("  ") {
      called = true
      SessionSnapshot()
    }
    assertEquals(AuthSessionPhase.SIGNED_OUT, blank.phase)
    assertFalse(called)

    val malformed = resolveAuthSession("bad room") { SessionSnapshot(sessionState = "active") }
    assertEquals(AuthSessionPhase.UNCONFIRMED, malformed.phase)

    val denied = resolveAuthSession("meridian-rehearsal") {
      throw MeridianError.HttpError(401, "unauthorized")
    }
    assertEquals(AuthSessionPhase.SIGNED_OUT, denied.phase)

    val forbidden = resolveAuthSession("meridian-rehearsal") {
      throw MeridianError.HttpError(403, "forbidden")
    }
    assertEquals(AuthSessionPhase.SIGNED_OUT, forbidden.phase)

    val server = resolveAuthSession("meridian-rehearsal") {
      throw MeridianError.HttpError(500, "down")
    }
    assertEquals(AuthSessionPhase.UNCONFIRMED, server.phase)

    val gateway = resolveAuthSession("meridian-rehearsal") {
      throw MeridianError.HttpError(504, "timeout")
    }
    assertEquals(AuthSessionPhase.UNCONFIRMED, gateway.phase)

    val transport = resolveAuthSession("meridian-rehearsal") {
      throw MeridianError.NetworkError("connection reset")
    }
    assertEquals(AuthSessionPhase.UNCONFIRMED, transport.phase)
    assertFalse(presentSessionBanner(transport).blocking)
  }

  @Test
  fun staleProbeCannotOverwriteANewerCheck() {
    val guard = SessionRefreshGuard()
    val first = guard.next()
    val second = guard.next()
    assertFalse(guard.isCurrent(first))
    assertTrue(guard.isCurrent(second))
    val late = AuthSession(AuthSessionPhase.SIGNED_OUT)
    val applied = if (guard.isCurrent(first)) late else AuthSession(AuthSessionPhase.ACTIVE)
    assertEquals(AuthSessionPhase.ACTIVE, applied.phase)
  }

  @Test
  fun healthPayloadKeepsSessionHintsAndIgnoresCorridorCopy() {
    val withHint = mapper.readValue(
      """
      {
        "status": "ok",
        "service": "meridian",
        "simulation": true,
        "sessionState": "expiring_soon",
        "accountName": "Ada",
        "deviceName": "Phone",
        "expiresAtEpochMs": 42
      }
      """.trimIndent(),
      HealthResponse::class.java,
    )
    assertEquals("expiring_soon", withHint.sessionState)
    assertEquals(42L, withHint.expiresAtEpochMs)
    val session = interpretSessionSnapshot(
      SessionSnapshot(
        sessionState = withHint.sessionState,
        accountName = withHint.accountName,
        deviceName = withHint.deviceName,
        expiresAtEpochMs = withHint.expiresAtEpochMs,
      ),
      nowEpochMs = 0,
    )
    assertEquals(AuthSessionPhase.EXPIRING, session.phase)

    val plain = mapper.readValue(
      """{"status":"ok","service":"meridian","simulation":true}""",
      HealthResponse::class.java,
    )
    assertNull(plain.sessionState)
    assertEquals(
      AuthSessionPhase.ACTIVE,
      interpretSessionSnapshot(SessionSnapshot(sessionState = plain.sessionState), nowEpochMs = 0).phase,
    )

    val extra = mapper.readValue(
      """{"status":"ok","service":"meridian","simulation":true,"launchNotice":"European launch"}""",
      HealthResponse::class.java,
    )
    assertNull(extra.sessionState)
    val banner = presentSessionBanner(AuthSession(AuthSessionPhase.ACTIVE))
    assertFalse(banner.title.contains("European"))
    assertFalse(banner.body.contains("launch"))
  }

  @Test
  fun probeUsesExistingSessionAndDoesNotCallAProvider() {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val paths = mutableListOf<String>()
    val sessions = mutableListOf<String>()
    server.createContext("/api/v1/health") { exchange ->
      paths += exchange.requestURI.path
      sessions += exchange.requestHeaders.getFirst("X-Rehearsal-Session")
      val payload = """{"status":"ok","service":"meridian","simulation":true,"sessionState":"active"}"""
      val bytes = payload.toByteArray()
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, bytes.size.toLong())
      exchange.responseBody.write(bytes)
      exchange.close()
    }
    server.createContext("/api/v1/payments") { exchange ->
      paths += exchange.requestURI.path
      exchange.sendResponseHeaders(500, -1)
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient("http://127.0.0.1:$port/api/v1", "meridian-rehearsal")
      val first = runBlocking { client.probeAuthSession() }
      val second = runBlocking { client.probeAuthSession() }
      assertEquals(AuthSessionPhase.ACTIVE, first.phase)
      assertEquals(AuthSessionPhase.ACTIVE, second.phase)
      assertEquals(listOf("meridian-rehearsal", "meridian-rehearsal"), sessions)
      assertTrue(paths.all { it == "/api/v1/health" })
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun httpUnauthorizedIsSignedOutAndTimeoutStaysNeutral() {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    server.createContext("/api/v1/health") { exchange ->
      val session = exchange.requestHeaders.getFirst("X-Rehearsal-Session")
      if (session == "expired-room") {
        val body = """{"error":"unauthorized"}""".toByteArray()
        exchange.sendResponseHeaders(401, body.size.toLong())
        exchange.responseBody.write(body)
        exchange.close()
      } else {
        Thread.sleep(1_500)
        val body = """{"status":"ok","service":"meridian","simulation":true}""".toByteArray()
        exchange.responseHeaders.add("Content-Type", "application/json")
        exchange.sendResponseHeaders(200, body.size.toLong())
        exchange.responseBody.write(body)
        exchange.close()
      }
    }
    server.start()
    try {
      val denied = MeridianClient("http://127.0.0.1:$port/api/v1", "expired-room")
      assertEquals(AuthSessionPhase.SIGNED_OUT, runBlocking { denied.probeAuthSession() }.phase)

      val slow = MeridianClient("http://127.0.0.1:$port/api/v1", "meridian-rehearsal")
      val started = System.currentTimeMillis()
      val result = runBlocking { slow.probeAuthSession(timeoutMs = 400) }
      val elapsed = System.currentTimeMillis() - started
      assertEquals(AuthSessionPhase.UNCONFIRMED, result.phase)
      assertFalse(presentSessionBanner(result).blocking)
      assertTrue("elapsed=$elapsed", elapsed < 3_000)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun elsewhereHintFromHealthTruncatesOnTheBanner() {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val device = "D".repeat(60)
    val account = "A".repeat(60)
    server.createContext("/api/v1/health") { exchange ->
      val payload = """
        {"status":"ok","service":"meridian","simulation":true,
         "sessionState":"active_elsewhere","accountName":"$account","deviceName":"$device"}
      """.trimIndent()
      val bytes = payload.toByteArray()
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, bytes.size.toLong())
      exchange.responseBody.write(bytes)
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient("http://127.0.0.1:$port/api/v1", "meridian-rehearsal")
      val session = runBlocking { client.probeAuthSession() }
      val banner = presentSessionBanner(session)
      assertEquals(AuthSessionPhase.ACTIVE_ELSEWHERE, banner.phase)
      assertFalse(banner.blocking)
      assertNull(banner.actionLabel)
      assertFalse(banner.body.contains(device))
      assertFalse(banner.body.contains(account))
      assertTrue(banner.body.contains("…"))
      assertTrue(meetsWcagAa(banner.foregroundArgb, banner.backgroundArgb))
    } finally {
      server.stop(0)
    }
  }
}
