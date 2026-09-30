package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.net.InetSocketAddress
import com.sun.net.httpserver.HttpServer

class PaymentStatusTest {
  private val mapper = ObjectMapper().registerKotlinModule()

  @Test
  fun backoffStaysInsideTheCap() {
    for (attempt in 0..12) {
      for (unit in listOf(0.0, 0.25, 0.5, 1.0)) {
        val delay = StatusBackoff.backoffMillis(attempt, unit)
        assertTrue(delay <= StatusBackoff.MAX_MS)
        assertTrue(delay >= StatusBackoff.INITIAL_MS / 2 || attempt > 0)
        assertTrue(delay <= StatusBackoff.MAX_MS)
      }
    }
    assertEquals(250L, StatusBackoff.backoffMillis(0, 0.0))
    assertEquals(500L, StatusBackoff.backoffMillis(0, 1.0))
    assertEquals(1_000L, StatusBackoff.backoffMillis(1, 1.0))
    assertEquals(2_000L, StatusBackoff.backoffMillis(2, 1.0))
    assertEquals(4_000L, StatusBackoff.backoffMillis(3, 1.0))
    assertEquals(4_000L, StatusBackoff.backoffMillis(10, 1.0))
    assertTrue(StatusBackoff.backoffMillis(2, 0.0) < StatusBackoff.backoffMillis(2, 1.0))
  }

  @Test
  fun classifiesProcessingPendingDeclinedAndSuccess() {
    assertEquals(IntentPhase.processing, IntentPhase.classify("processing"))
    assertEquals(IntentPhase.processing, IntentPhase.classify("submitting"))
    assertEquals(IntentPhase.pending, IntentPhase.classify("pending"))
    assertEquals(IntentPhase.unknown, IntentPhase.classify("not-a-status"))
    assertEquals(IntentPhase.unknown, IntentPhase.classify(null))
    assertEquals(IntentPhase.succeeded, IntentPhase.classify("completed"))
    assertEquals(IntentPhase.declined, IntentPhase.classify("declined-final"))
    assertEquals(IntentPhase.declined, IntentPhase.classify("PAYMENT_DECLINED"))
    assertEquals(IntentPhase.pending, phaseFor(PaymentResponse(ok = false, code = "PAYMENT_PENDING", paymentId = "pi-1")))
    assertEquals(IntentPhase.declined, phaseFor(PaymentResponse(ok = false, code = "PAYMENT_DECLINED")))
    assertEquals(IntentPhase.succeeded, phaseFor(PaymentResponse(ok = true)))
    assertEquals(IntentPhase.unknown, phaseFor(PaymentResponse(ok = false, code = "PROVIDER_UNAVAILABLE")))
  }

  @Test
  fun nonGbpSuccessIsNotAReceipt() {
    val phase = presentationPhase(PaymentIntent(id = "pi-1", status = "succeeded", currency = "EUR", amountMinor = 100))
    assertEquals(IntentPhase.unknown, phase)
  }

  @Test
  fun recoveryResumesChecksAndDoesNotResubmitDecline() {
    val open = sampleSnapshot(phase = IntentPhase.processing, intentId = "pi-open")
    val pending = sampleSnapshot(phase = IntentPhase.pending, intentId = "pi-pending")
    val unknown = sampleSnapshot(phase = IntentPhase.unknown, intentId = "pi-unknown")
    val declined = sampleSnapshot(phase = IntentPhase.declined, intentId = "pi-no")
    val missing = sampleSnapshot(phase = IntentPhase.unknown, intentId = null)
    assertEquals(RecoveryAction.Poll("pi-open"), recoveryAction(open))
    assertEquals(RecoveryAction.Poll("pi-pending"), recoveryAction(pending))
    assertEquals(RecoveryAction.Poll("pi-unknown"), recoveryAction(unknown))
    assertEquals(RecoveryAction.ShowDecline, recoveryAction(declined))
    assertEquals(RecoveryAction.HoldUnknown, recoveryAction(missing))
    assertTrue(recoveryFeedback(IntentPhase.declined).contains("will not be submitted again"))
  }

  @Test
  fun receiptIncludesRecipientAmountAndSupportReference() {
    val snapshot = sampleSnapshot(phase = IntentPhase.succeeded, intentId = "pi-1").copy(
      supportReference = null,
      transaction = null,
    )
    val intent = PaymentIntent(
      id = "pi-1",
      status = "succeeded",
      amountMinor = 2599,
      currency = "GBP",
      recipientName = "Northline Studio",
      supportReference = "SUP-140-7781",
      method = "card",
      provider = "adyen",
      note = "Materials",
    )
    val receipt = makeReceipt(snapshot, intent)
    assertEquals("Northline Studio", receipt.recipientName)
    assertEquals(2599, receipt.amountMinor)
    assertEquals("SUP-140-7781", receipt.supportReference)
    assertEquals("Materials", receipt.note)
    assertEquals("Adyen", providerLabel(receipt.provider))
  }

  @Test
  fun pollStopsOnDeclineAndKeepsPollingProcessingPendingAndUnknown() = runBlocking {
    val sleeps = mutableListOf<Long>()
    var calls = 0
    val declined = PaymentStatusPoller(
      getIntent = {
        calls += 1
        PaymentIntent(id = "pi-1", status = "declined", error = "Payment declined")
      },
      sleep = { sleeps += it },
      randomUnit = { 1.0 },
    )
    val decline = declined.poll("pi-1")
    assertEquals(IntentPhase.declined, decline.phase)
    assertEquals(1, decline.attempts)
    assertEquals(1, calls)
    assertTrue(sleeps.isEmpty())

    calls = 0
    val script = ArrayDeque(listOf("processing", "pending", "mystery", "succeeded"))
    val continued = PaymentStatusPoller(
      getIntent = {
        calls += 1
        PaymentIntent(
          id = "pi-2",
          status = script.removeFirst(),
          amountMinor = 1500,
          currency = "GBP",
          recipientName = "Northline Studio",
          supportReference = "SUP-9",
        )
      },
      sleep = { sleeps += it },
      randomUnit = { 0.0 },
      maxElapsedMs = 60_000,
    )
    val done = continued.poll("pi-2")
    assertEquals(IntentPhase.succeeded, done.phase)
    assertEquals(4, calls)
    assertEquals(3, sleeps.size)
    assertTrue(sleeps.all { it <= StatusBackoff.MAX_MS })
    assertEquals("SUP-9", applying(done, sampleSnapshot(IntentPhase.processing, "pi-2")).supportReference)
  }

  @Test
  fun elapsedBudgetStopsWithoutAnotherPayment() = runBlocking {
    var calls = 0
    val poller = PaymentStatusPoller(
      getIntent = {
        calls += 1
        PaymentIntent(id = "pi-3", status = "processing")
      },
      sleep = { throw IllegalStateException("should not sleep past the elapsed budget") },
      randomUnit = { 1.0 },
      maxElapsedMs = 0,
    )
    val result = poller.poll("pi-3")
    assertEquals(IntentPhase.processing, result.phase)
    assertEquals(1, calls)
  }

  @Test
  fun lookupUsesV2AndDoesNotPost() {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    val methods = mutableListOf<String>()
    val paths = mutableListOf<String>()
    var hits = 0
    server.createContext("/api/v2/payment-intents/pi-77") { exchange ->
      methods += exchange.requestMethod
      paths += exchange.requestURI.path
      val session = exchange.requestHeaders.getFirst("X-Rehearsal-Session")
      assertEquals("room-1", session)
      hits += 1
      val body = if (hits == 1) {
        """{"id":"pi-77","status":"processing","currency":"GBP","amountMinor":1000}"""
      } else {
        """{"id":"pi-77","status":"declined","currency":"GBP","amountMinor":1000,"error":"Payment declined"}"""
      }
      val bytes = body.toByteArray()
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, bytes.size.toLong())
      exchange.responseBody.write(bytes)
      exchange.close()
    }
    server.start()
    try {
      val base = "http://127.0.0.1:${server.address.port}/api/v1"
      assertEquals(
        "http://127.0.0.1:${server.address.port}/api/v2/payment-intents/pi-77",
        paymentIntentUrl(base, "pi-77"),
      )
      val client = MeridianClient(base, "room-1")
      val result = runBlocking {
        PaymentStatusPoller(
          getIntent = { client.getPaymentIntent(it) },
          sleep = {},
          randomUnit = { 0.0 },
        ).poll("pi-77")
      }
      assertEquals(IntentPhase.declined, result.phase)
      assertEquals(listOf("GET", "GET"), methods)
      assertTrue(paths.all { it == "/api/v2/payment-intents/pi-77" })
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun snapshotSurvivesRestartAndPrefersOpenIntent() {
    val file = File.createTempFile("meridian-intents", ".json")
    file.deleteOnExit()
    val store = FileIntentSnapshotStore(file)
    val declined = sampleSnapshot(IntentPhase.declined, "pi-old").copy(sessionId = "room-a", updatedAt = "2026-09-18T10:00:00Z")
    val open = sampleSnapshot(IntentPhase.pending, "pi-new").copy(sessionId = "room-b", updatedAt = "2026-09-18T11:00:00Z")
    store.save(declined)
    store.save(open)
    val reloaded = FileIntentSnapshotStore(file)
    assertEquals("pi-new", reloaded.latestRecoverable()?.intentId)
    assertEquals(RecoveryAction.Poll("pi-new"), recoveryAction(reloaded.load("room-b")!!))
    reloaded.remove("room-b")
    assertEquals("pi-old", reloaded.latestRecoverable()?.intentId)
    assertEquals(RecoveryAction.ShowDecline, recoveryAction(reloaded.load("room-a")!!))
    file.writeText("{not json")
    assertNull(FileIntentSnapshotStore(file).latestRecoverable())
  }

  @Test
  fun decodesIntentStatusFromPhaseField() {
    val intent = mapper.readValue(
      """{"id":"pi-8","phase":"pending","amountMinor":500,"currency":"GBP"}""",
      PaymentIntent::class.java,
    )
    assertEquals(IntentPhase.pending, presentationPhase(intent))
  }

  private fun sampleSnapshot(phase: IntentPhase, intentId: String?) = IntentSnapshot(
    intentId = intentId,
    sessionId = "room-1",
    baseURL = "http://127.0.0.1:8080/api/v1",
    idempotencyKey = "11111111-1111-4111-8111-111111111111",
    recipientId = "northline-studio",
    recipientName = "Northline Studio",
    amountMinor = 1500,
    method = "card",
    note = "Materials",
    phase = phase,
    provider = "adyen",
    updatedAt = "2026-09-18T12:00:00Z",
  )
}
