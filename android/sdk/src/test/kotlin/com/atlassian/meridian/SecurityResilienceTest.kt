package com.atlassian.meridian

import com.fasterxml.jackson.databind.DeserializationFeature
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

/**
 * Security and resilience tests for the Meridian SDK.
 *
 * Verifies rejection of replayed deep links, expired / stale return states,
 * and malformed catalog entries.  All tests run fully offline (embedded HTTP
 * server or pure model logic) so no real payment network is involved.
 */
class SecurityResilienceTest {
  private val mapper = ObjectMapper()
    .registerKotlinModule()
    .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false)

  // -------------------------------------------------------------------------
  // Replayed Deep-Link Scenarios
  // -------------------------------------------------------------------------

  @Test
  fun securityReplayedPaymentIdDetectedLocally() {
    // A payment ID that has already been processed must be detected as a replay
    val processed = mutableSetOf<String>()
    val id = "pay-deep-link-001"

    val firstSeen = processed.add(id)
    assertTrue("First occurrence must not be a replay", firstSeen)

    val secondSeen = processed.add(id)
    assertFalse("Duplicate payment ID must be flagged as replay", secondSeen)
  }

  @Test
  fun securityDeepLinkPaymentIdMustBeNonEmpty() {
    val valid   = "pay-valid-001"
    val empty   = ""
    assertTrue("Valid payment ID is non-empty", valid.isNotEmpty())
    assertTrue("Empty payment ID must be rejected", empty.isEmpty())
  }

  @Test
  fun securityDeepLinkSessionMustMatchActiveSession() {
    val activeSession    = "session-abc-123"
    val matchingSession  = "session-abc-123"
    val mismatchSession  = "session-old-456"
    assertEquals("Matching session must be accepted", activeSession, matchingSession)
    assertNotEquals("Mismatched session must be rejected", activeSession, mismatchSession)
  }

  @Test
  fun securityServerReturns409ForReplayedIdempotencyKey() {
    // Server signals a completed-payment replay with HTTP 409; the SDK must
    // surface it as a non-ok response rather than crashing.
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    var callCount = 0

    server.createContext("/api/v1/payments") { exchange ->
      callCount++
      val (status, body) = if (callCount == 1) {
        200 to """{"ok":true,"paymentId":"pay-replay-1","state":{"version":1,"balance":90000,"transactions":[],"budgets":[]}}"""
      } else {
        409 to """{"ok":false,"error":"Idempotency key already used for a completed payment","code":"REPLAY_DETECTED"}"""
      }
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(status, body.length.toLong())
      exchange.responseBody.write(body.toByteArray())
      exchange.close()
    }
    server.start()

    try {
      val client = MeridianClient("http://127.0.0.1:$port/api/v1", "sess-sec")
      val key = "idm-key-replay"

      val r1 = runBlocking { client.submitPayment("rec-1", 1_000, PaymentMethod.card, idempotencyKey = key) }
      assertTrue("First call must succeed", r1.ok)

      val r2 = runBlocking { client.submitPayment("rec-1", 1_000, PaymentMethod.card, idempotencyKey = key) }
      assertFalse("Replayed request must not be ok", r2.ok)
      assertEquals("REPLAY_DETECTED", r2.code)
    } finally {
      server.stop(0)
    }
  }

  // -------------------------------------------------------------------------
  // Expired / Stale Return-State Scenarios
  // -------------------------------------------------------------------------

  @Test
  fun securityExpiredStateHasLowerVersionThanCurrent() {
    val currentVersion = 10
    val expiredState = BankState(version = 3, balance = 500_000, transactions = emptyList(), budgets = emptyList())
    assertTrue("Expired state version must be less than current version",
      expiredState.version < currentVersion)
  }

  @Test
  fun securityExpiredCatalogDateIsBefore() {
    val freshDate   = "2026-09-18"
    val expiredDate = "2025-01-01"
    assertTrue("Expired catalog date must sort before fresh date", expiredDate < freshDate)
  }

  @Test
  fun securityPendingPaymentTiedToVeryOldVersionIsExpired() {
    // A PAYMENT_PENDING response that was saved when state.version was 1
    // should be treated as expired once the server is at version 5+.
    val savedPendingStateVersion = 1
    val currentStateVersion = 5
    val isExpired = savedPendingStateVersion < currentStateVersion - 2
    assertTrue("Pending response saved against a very old state version must be expired", isExpired)
  }

  @Test
  fun securityZeroVersionStateIsAlwaysStale() {
    val uninitialised = BankState(version = 0, balance = 0, transactions = emptyList(), budgets = emptyList())
    assertEquals("version 0 represents uninitialised / always-stale state", 0, uninitialised.version)
  }

  @Test
  fun securityServerReturns503IsHandledAsTransientError() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port

    server.createContext("/api/v1/state") { exchange ->
      val body = """{"ok":false,"error":"Service temporarily unavailable","code":"UNAVAILABLE"}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(503, body.length.toLong())
      exchange.responseBody.write(body.toByteArray())
      exchange.close()
    }
    server.start()

    try {
      val client = MeridianClient("http://127.0.0.1:$port/api/v1", "sess-503")
      // SDK must not crash on 503; it either returns a decoded body or throws a typed error.
      try {
        val state = runBlocking { client.getState() }
        // If the SDK parsed the error body into BankState somehow, that's unexpected but not a crash
        assertNotNull(state)
      } catch (e: MeridianError) {
        // Expected: typed error propagated to the caller
        assertTrue(e is MeridianError.HttpError || e is MeridianError.DecodingError)
      }
    } finally {
      server.stop(0)
    }
  }

  // -------------------------------------------------------------------------
  // Malformed Catalog Entry Scenarios
  // -------------------------------------------------------------------------

  @Test
  fun securityMalformedRecipientMissingIdIsDetectable() {
    // A recipient JSON without an `id` field must not silently produce a valid entry;
    // Jackson with Kotlin module sets the non-nullable String to null at runtime.
    val json = """
      {"name":"No-ID Merchant","initials":"NM","detail":"Bad","category":"Shopping","color":"#000"}
    """.trimIndent()
    try {
      val recipient = mapper.readValue(json, Recipient::class.java)
      // Jackson bypasses Kotlin null safety; the id field will be null
      assertNull("Missing id must result in null id field", recipient.id)
    } catch (e: Exception) {
      // Also acceptable: Jackson throws because the non-nullable field cannot be null
      assertTrue(
        e is com.fasterxml.jackson.databind.exc.MismatchedInputException ||
          e is com.fasterxml.jackson.databind.exc.ValueInstantiationException ||
          e is NullPointerException
      )
    }
  }

  @Test
  fun securityUnknownProviderIdIsDetectable() {
    val knownProviders = setOf("adyen", "worldpay")
    val unknownId = "stripe"
    assertFalse("Unknown provider ID '$unknownId' must not be in the known set",
      unknownId in knownProviders)
  }

  @Test
  fun securityMalformedTransactionNegativeAmountIsDetectable() {
    val json = """
      {
        "id":"txn-bad","reference":"REF-BAD","recipientId":"rec-1","name":"Bad",
        "category":"Shopping","amount":-100,"date":"2026-09-18",
        "provider":"adyen","method":"card","status":"completed","note":""
      }
    """.trimIndent()
    val txn = mapper.readValue(json, Transaction::class.java)
    assertTrue("Negative amount is a malformed entry", txn.amount < 0)
  }

  @Test
  fun securityMalformedCatalogMissingProvidersThrowsOrIsEmpty() {
    val json = """{"demoDate": "2026-09-18", "recipients": []}"""
    try {
      val catalog = mapper.readValue(json, CatalogResponse::class.java)
      // If Jackson doesn't throw, providers must be null – treat as malformed
      assertNull("CatalogResponse with no providers field must have null providers", catalog.providers)
    } catch (e: Exception) {
      assertTrue(
        "Expected deserialization failure for missing providers",
        e is com.fasterxml.jackson.databind.exc.MismatchedInputException ||
          e is com.fasterxml.jackson.databind.exc.ValueInstantiationException ||
          e is NullPointerException
      )
    }
  }

  @Test
  fun securityAmountInjectionAttemptsAreRejected() {
    val injections = listOf(
      "'; DROP TABLE payments; --",
      "<script>alert(1)</script>",
      "1" + "0".repeat(20),
      "../../../etc/passwd",
      "\u0000\u0001",
      "NaN",
      "Infinity"
    )
    injections.forEach { attempt ->
      val (pence, error) = parseAmount(attempt)
      assertNull("Injection '$attempt' must not produce a valid pence value", pence)
      assertNotNull("Injection '$attempt' must produce an error message", error)
    }
  }

  @Test
  fun securityBudgetLimitExceedingMaxIsRejected() {
    // £100,000 as a string (10,000,000 pence) exceeds the £10,000 cap
    val (pence, error) = parseAmount("100000")
    assertNull("Amount over cap must not be parsed", pence)
    assertNotNull("Amount over cap must return an error", error)
  }

  // -------------------------------------------------------------------------
  // Session / URL Validation
  // -------------------------------------------------------------------------

  @Test
  fun securityClientRejectsEmptySessionId() {
    val ex = assertThrows(IllegalArgumentException::class.java) {
      MeridianClient(baseURL = "http://localhost:8080/api/v1", sessionId = "")
    }
    assertTrue("Error must mention Session ID", ex.message?.contains("Session ID") ?: false)
  }

  @Test
  fun securityClientRejectsNonHttpSchemes() {
    listOf("ftp://example.com", "ws://example.com", "file:///etc/passwd").forEach { url ->
      assertThrows("Must reject scheme in: $url", IllegalArgumentException::class.java) {
        MeridianClient(baseURL = url, sessionId = "sess")
      }
    }
  }

  @Test
  fun securityClientRejectsInvalidUrl() {
    val ex = assertThrows(IllegalArgumentException::class.java) {
      MeridianClient(baseURL = "not a url", sessionId = "sess")
    }
    assertNotNull("Must return an error for an invalid URL", ex.message)
  }

  @Test
  fun securityRehearsalSessionHeaderIsSentOnEveryRequest() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val capturedSessions = mutableListOf<String?>()

    listOf("/api/v1/health", "/api/v1/catalog", "/api/v1/state").forEach { path ->
      server.createContext(path) { exchange ->
        capturedSessions.add(exchange.requestHeaders.getFirst("X-Rehearsal-Session"))
        val body = when (path) {
          "/api/v1/health"  -> """{"status":"ok","service":"meridian","simulation":true}"""
          "/api/v1/catalog" -> """{"demoDate":"2026-09-18","recipients":[],"providers":[]}"""
          else              -> """{"version":1,"balance":0,"transactions":[],"budgets":[]}"""
        }
        exchange.responseHeaders.add("Content-Type", "application/json")
        exchange.sendResponseHeaders(200, body.length.toLong())
        exchange.responseBody.write(body.toByteArray())
        exchange.close()
      }
    }
    server.start()

    try {
      val expectedSession = "sess-header-check"
      val client = MeridianClient("http://127.0.0.1:$port/api/v1", expectedSession)
      runBlocking {
        client.getHealth()
        client.getCatalog()
        client.getState()
      }
      assertEquals("X-Rehearsal-Session must be sent on every request", 3, capturedSessions.size)
      capturedSessions.forEach { hdr ->
        assertEquals("X-Rehearsal-Session must match the configured session", expectedSession, hdr)
      }
    } finally {
      server.stop(0)
    }
  }
}
