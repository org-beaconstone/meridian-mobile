package com.atlassian.meridian

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.net.InetSocketAddress
import com.sun.net.httpserver.HttpServer

class IdempotencyKeyManagerTest {
  @Test
  fun testSecureUuidV4ShapeAndUniqueness() {
    val keys = List(64) { IdempotencyKeyManager.secureUuidV4() }
    assertEquals(64, keys.toSet().size)
    keys.forEach { key ->
      assertTrue(IdempotencyKeyManager.isUuidV4(key))
      assertEquals(36, key.length)
    }
  }

  @Test
  fun testTtlMatchesTwentyFourHours() {
    assertEquals(86_400_000L, IdempotencyKeyManager.TWENTY_FOUR_HOURS_MILLIS)
  }

  @Test
  fun testBeginRetryAndChallengeReuseOneKey() {
    var generated = 0
    val manager = manager(clock = { 1_000L }, generator = {
      generated += 1
      uuid(generated)
    })
    val fingerprint = attempt().fingerprint()
    val key = manager.begin("tx-1", fingerprint)
    assertEquals(uuid(1), key)
    assertEquals(key, manager.keyForRetry("tx-1", fingerprint))
    assertEquals(key, manager.keyForChallenge("tx-1", fingerprint))
    assertEquals(key, manager.activeKey("tx-1"))
    assertEquals(1, generated)
  }

  @Test
  fun testSeparateAttemptsGetSeparateKeys() {
    val manager = IdempotencyKeyManager()
    val first = manager.begin("tx-1")
    val second = manager.begin("tx-2")
    assertNotEquals(first, second)
    assertTrue(IdempotencyKeyManager.isUuidV4(first))
    assertTrue(IdempotencyKeyManager.isUuidV4(second))
  }

  @Test
  fun testSettleAndCancelPurgeTheCache() {
    val manager = manager(clock = { 5_000L })
    manager.begin("settled")
    manager.begin("cancelled")
    manager.settle("settled")
    manager.cancel("cancelled")
    assertNull(manager.activeKey("settled"))
    assertNull(manager.activeKey("cancelled"))
    assertTrue(manager.storedRecords().isEmpty())
    assertThrows(MeridianError.MissingIdempotencyKey::class.java) {
      manager.keyForRetry("settled")
    }
    assertThrows(MeridianError.MissingIdempotencyKey::class.java) {
      manager.keyForChallenge("cancelled")
    }
  }

  @Test
  fun testExpiredKeyIsNotAttached() {
    var now = 10_000L
    val manager = manager(clock = { now })
    val key = manager.begin("tx-1", attempt().fingerprint())
    now = 10_000L + IdempotencyKeyManager.TWENTY_FOUR_HOURS_MILLIS - 1
    assertEquals(key, manager.keyForRetry("tx-1", attempt().fingerprint()))
    now = 10_000L + IdempotencyKeyManager.TWENTY_FOUR_HOURS_MILLIS
    val expired = assertThrows(MeridianError.IdempotencyKeyExpired::class.java) {
      manager.keyForRetry("tx-1", attempt().fingerprint())
    }
    assertEquals("tx-1", expired.transactionId)
    assertThrows(MeridianError.IdempotencyKeyExpired::class.java) {
      manager.keyForChallenge("tx-1")
    }
    assertNull(manager.activeKey("tx-1"))
    assertEquals(1, manager.storedRecords().size)
    assertEquals(key, manager.storedRecords().single().key)
  }

  @Test
  fun testFingerprintMismatchDoesNotRotateTheKey() {
    val manager = manager(clock = { 50L })
    val original = attempt()
    val key = manager.begin("tx-1", original.fingerprint())
    val changed = original.copy(amountMinor = 200)
    assertThrows(MeridianError.ValidationError::class.java) {
      manager.keyForRetry("tx-1", changed.fingerprint())
    }
    assertEquals(key, manager.keyForChallenge("tx-1", original.fingerprint()))
  }

  @Test
  fun testFingerprintRoundTripKeepsNoteText() {
    val attempt = PaymentAttempt(
      recipientId = "northline-studio",
      amountMinor = 2599,
      method = "card",
      note = "line\\one\u001fnext",
      scenario = "success",
    )
    val decoded = PaymentAttempt.fromFingerprint(attempt.fingerprint())
    assertEquals(attempt, decoded)
  }

  @Test
  fun testFileStoreSurvivesANewManager() {
    val directory = File(System.getProperty("java.io.tmpdir"), "meridian-idempotency-${System.nanoTime()}")
    directory.mkdirs()
    try {
      val file = FileIdempotencyStore.fileFor(directory, "room/1")
      val clock = { 4_000L }
      val first = IdempotencyKeyManager(FileIdempotencyStore(file), clock = clock)
      val key = first.begin("tx-9", attempt().fingerprint())
      val second = IdempotencyKeyManager(FileIdempotencyStore(file), clock = clock)
      assertEquals(key, second.keyForRetry("tx-9", attempt().fingerprint()))
      second.settle("tx-9")
      val third = IdempotencyKeyManager(FileIdempotencyStore(file), clock = clock)
      assertTrue(third.storedRecords().isEmpty())
    } finally {
      directory.deleteRecursively()
    }
  }

  @Test
  fun testManagedPaymentHeadersRetriesChallengeAndSettlement() {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    val keys = mutableListOf<String>()
    var hits = 0
    server.createContext("/api/v1/payments") { exchange ->
      hits += 1
      val key = exchange.requestHeaders.getFirst("Idempotency-Key")
      keys.add(key ?: "")
      val pending = hits < 4
      val body = if (pending) {
        """{"ok":false,"code":"PAYMENT_PENDING","paymentId":"pay-1","error":"Awaiting confirmation"}"""
      } else {
        """{"ok":true,"paymentId":"pay-1","transaction":{"id":"txn-1","reference":"r","recipientId":"rec-1","name":"Northline","category":"Shopping","amount":100,"date":"2026-10-04","provider":"adyen","method":"card","status":"completed","note":""}}"""
      }
      val status = if (pending) 202 else 200
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(status, body.length.toLong())
      exchange.responseBody.write(body.toByteArray())
      exchange.close()
    }
    server.start()
    try {
      var generated = 0
      val manager = manager(clock = { 9_000L }, generator = {
        generated += 1
        uuid(generated)
      })
      val client = MeridianClient("http://127.0.0.1:${server.address.port}/api/v1", "test-session", manager)
      val first = runBlocking {
        client.submitPayment(
          recipientId = "rec-1",
          amountMinor = 100,
          method = PaymentMethod.card,
          transactionId = "local-1",
        )
      }
      assertFalse(first.ok)
      val retried = runBlocking {
        client.retryPayment("local-1", "rec-1", 100, PaymentMethod.card)
      }
      assertFalse(retried.ok)
      val challenged = runBlocking {
        client.submitChallenge("local-1", "rec-1", 100, PaymentMethod.card)
      }
      assertFalse(challenged.ok)
      assertEquals(listOf(uuid(1), uuid(1), uuid(1)), keys)
      assertEquals(1, generated)

      val settled = runBlocking {
        client.submitPayment(
          recipientId = "rec-1",
          amountMinor = 100,
          method = PaymentMethod.card,
          transactionId = "local-1",
        )
      }
      assertTrue(settled.ok)
      assertEquals(uuid(1), keys[3])
      assertTrue(manager.storedRecords().isEmpty())

      val hitsAfterSettlement = hits
      val missing = assertThrows(MeridianError.MissingIdempotencyKey::class.java) {
        runBlocking { client.retryPayment("local-1", "rec-1", 100, PaymentMethod.card) }
      }
      assertEquals("local-1", missing.transactionId)
      assertThrows(MeridianError.MissingIdempotencyKey::class.java) {
        runBlocking { client.submitChallenge("local-1", "rec-1", 100, PaymentMethod.card) }
      }
      assertEquals(hitsAfterSettlement, hits)

      client.preparePayment("local-3", "rec-1", 100, PaymentMethod.card)
      assertThrows(MeridianError.ValidationError::class.java) {
        runBlocking { client.retryPayment("local-3", "rec-1", 250, PaymentMethod.card) }
      }
      assertEquals(hitsAfterSettlement, hits)
      assertEquals(uuid(2), manager.activeKey("local-3"))
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testExpiredInFlightPaymentIsNotSent() {
    var now = 0L
    val manager = manager(clock = { now })
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    var hits = 0
    server.createContext("/api/v1/payments") { exchange ->
      hits += 1
      val body = """{"ok":false,"code":"PAYMENT_PENDING","paymentId":"pay-2","error":"pending"}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(202, body.length.toLong())
      exchange.responseBody.write(body.toByteArray())
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient("http://127.0.0.1:${server.address.port}/api/v1", "room-1", manager)
      runBlocking {
        client.preparePayment("local-9", "rec-1", 100, PaymentMethod.bank)
        client.submitPayment(
          recipientId = "rec-1",
          amountMinor = 100,
          method = PaymentMethod.bank,
          transactionId = "local-9",
        )
      }
      assertEquals(1, hits)
      now = IdempotencyKeyManager.TWENTY_FOUR_HOURS_MILLIS
      assertThrows(MeridianError.IdempotencyKeyExpired::class.java) {
        runBlocking {
          client.retryPayment("local-9", "rec-1", 100, PaymentMethod.bank)
        }
      }
      assertThrows(MeridianError.IdempotencyKeyExpired::class.java) {
        runBlocking {
          client.submitChallenge("local-9", "rec-1", 100, PaymentMethod.bank)
        }
      }
      assertEquals(1, hits)
      assertEquals(1, manager.storedRecords().size)
    } finally {
      server.stop(0)
    }
  }

  private fun attempt() = PaymentAttempt("rec-1", 100, "card", "note", "success")

  private fun manager(
    clock: () -> Long,
    generator: () -> String = { uuid(1) },
  ) = IdempotencyKeyManager(
    store = MemoryIdempotencyStore(),
    clock = clock,
    uuidGenerator = generator,
  )

  private fun uuid(sequence: Int) =
    "00000000-0000-4000-8000-${sequence.toString().padStart(12, '0')}"
}
