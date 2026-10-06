package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PaymentIntentSnapshotTest {
  private val mapper = ObjectMapper().registerKotlinModule()

  @Test
  fun testBusinessPayloadHashVector() {
    val canonical = PaymentIntentHash.canonicalBusinessPayload(
      customerAccountId = "acct-demo",
      recipientId = "northline-studio",
      amountMinor = 2599,
      method = "card",
      note = "Studio invoice",
      scenario = "success",
    )
    assertEquals(
      """{"v":1,"customerAccountId":"acct-demo","recipientId":"northline-studio","amountMinor":2599,"method":"card","note":"Studio invoice","scenario":"success"}""",
      canonical,
    )
    assertEquals(
      "ae1c0e96711da9a13695fd7439b2b60ff0a3bf9c3f336729fe5cb3eb98ae642e",
      PaymentIntentHash.sha256Hex(canonical),
    )
  }

  @Test
  fun testBusinessPayloadHashEscapesNote() {
    val note = "line\nquote\""
    val canonical = PaymentIntentHash.canonicalBusinessPayload(
      "acct-demo",
      "northline-studio",
      100,
      "bank",
      note,
      "pending",
    )
    assertEquals(
      "{\"v\":1,\"customerAccountId\":\"acct-demo\",\"recipientId\":\"northline-studio\",\"amountMinor\":100,\"method\":\"bank\",\"note\":\"line\\nquote\\\"\",\"scenario\":\"pending\"}",
      canonical,
    )
    assertEquals(
      "882dc93278f448b32d5782b4312660ebc3f80f7aed5fed70ae82d1495f5f72fd",
      PaymentIntentHash.sha256Hex(canonical),
    )
  }

  @Test
  fun testReturnStateHash() {
    assertEquals(
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      PaymentIntentHash.returnStateHash("abc"),
    )
  }

  @Test
  fun testRestartResumesSameIdempotencyKeyAndHidesOtherAccounts() {
    val clock = Clock()
    val (store, ledger) = ledger(clock)
    val prepared = ledger.begin("acct-demo", "northline-studio", 2599, "card", "Studio invoice", "success")
    assertTrue(ledger.verifyReturnState(prepared.snapshot, prepared.returnState!!))
    val submitted = ledger.markSubmitted("acct-demo", prepared.snapshot.paymentIntentId)
    val pending = ledger.record(
      PaymentResponse(ok = false, code = "PAYMENT_PENDING", error = "Payment pending confirmation", paymentId = "pay-1"),
      "acct-demo",
      submitted.paymentIntentId,
    )
    assertEquals(PaymentIntentStatus.pending, pending.status)
    ledger.begin("other-acct", "northline-studio", 100, "bank", "other", "success")

    val restarted = PaymentIntentLedger(store, nowMillis = { clock.now })
    val active = restarted.activeIntents("acct-demo")
    assertEquals(1, active.size)
    assertEquals(prepared.snapshot.paymentIntentId, active[0].paymentIntentId)
    assertEquals(prepared.snapshot.idempotencyKey, active[0].idempotencyKey)
    assertEquals(prepared.snapshot.businessPayloadHash, active[0].businessPayloadHash)
    assertEquals(prepared.snapshot.returnStateHash, active[0].returnStateHash)
    assertTrue(restarted.activeIntents("other-acct").none { it.paymentIntentId == prepared.snapshot.paymentIntentId })
    assertEquals("other-acct", restarted.lastCustomerAccountId())
  }

  @Test
  fun testTerminalRetentionWindow() {
    val clock = Clock(1_000)
    val (store, ledger) = ledger(clock, retentionMillis = 1_000)
    val prepared = ledger.begin("acct-demo", "northline-studio", 500, "card", "", "success")
    ledger.markSubmitted("acct-demo", prepared.snapshot.paymentIntentId)
    val done = ledger.record(
      PaymentResponse(ok = true, paymentId = "pay-9"),
      "acct-demo",
      prepared.snapshot.paymentIntentId,
    )
    assertEquals(PaymentIntentStatus.completed, done.status)
    assertEquals(1_000L, done.terminalAtEpochMillis)
    clock.now = 1_999
    val restarted = PaymentIntentLedger(store, nowMillis = { clock.now }, retentionMillis = 1_000)
    assertTrue(restarted.activeIntents("acct-demo").isEmpty())
    assertEquals(1, restarted.snapshots("acct-demo").size)
    clock.now = 2_000
    assertTrue(restarted.snapshots("acct-demo").isEmpty())
    assertTrue(store.load("acct-demo").isEmpty())
  }

  @Test
  fun testActiveIntentDoesNotExpireAndPurgeIsAccountScoped() {
    val clock = Clock(0)
    val (_, ledger) = ledger(clock, retentionMillis = 1_000)
    val kept = ledger.begin("acct-demo", "northline-studio", 500, "card", "", "success")
    val other = ledger.begin("other-acct", "northline-studio", 500, "card", "", "success")
    ledger.markSubmitted("other-acct", other.snapshot.paymentIntentId)
    ledger.record(PaymentResponse(ok = true), "other-acct", other.snapshot.paymentIntentId)
    clock.now = 50_000
    assertEquals(kept.snapshot.paymentIntentId, ledger.activeIntents("acct-demo").single().paymentIntentId)
    assertTrue(ledger.snapshots("other-acct").isEmpty())
    assertEquals(1, ledger.snapshots("acct-demo").size)
  }

  @Test
  fun testUncertainRetryKeepsIdempotencyKey() {
    val (_, ledger) = ledger()
    val prepared = ledger.begin("acct-demo", "northline-studio", 2599, "bank", "rent", "success")
    ledger.markSubmitted("acct-demo", prepared.snapshot.paymentIntentId)
    val uncertain = ledger.markUncertain("acct-demo", prepared.snapshot.paymentIntentId)
    assertEquals(PaymentIntentStatus.unknown, uncertain.status)
    assertEquals(prepared.snapshot.idempotencyKey, uncertain.idempotencyKey)
    assertNull(uncertain.terminalAtEpochMillis)
    assertEquals(uncertain.paymentIntentId, ledger.activeIntents("acct-demo").single().paymentIntentId)
  }

  @Test
  fun testSamePayloadReusesIntent() {
    val (_, ledger) = ledger()
    val first = ledger.begin("acct-demo", "northline-studio", 2599, "card", "Studio invoice", "success")
    val second = ledger.begin("acct-demo", "northline-studio", 2599, "card", "Studio invoice", "success")
    assertNull(second.returnState)
    assertEquals(first.snapshot.paymentIntentId, second.snapshot.paymentIntentId)
    assertEquals(first.snapshot.idempotencyKey, second.snapshot.idempotencyKey)
    assertEquals(1, ledger.activeIntents("acct-demo").size)
  }

  @Test
  fun testInFlightIntentBlocksDifferentPayload() {
    val (_, ledger) = ledger()
    val prepared = ledger.begin("acct-demo", "northline-studio", 2599, "card", "Studio invoice", "success")
    ledger.markSubmitted("acct-demo", prepared.snapshot.paymentIntentId)
    ledger.record(
      PaymentResponse(ok = false, code = "PAYMENT_PENDING"),
      "acct-demo",
      prepared.snapshot.paymentIntentId,
    )
    try {
      ledger.begin("acct-demo", "northline-studio", 100, "card", "Studio invoice", "success")
      throw AssertionError("expected active intent to block a different payload")
    } catch (e: ActivePaymentIntentException) {
      assertEquals(prepared.snapshot.paymentIntentId, e.paymentIntentId)
    }
    assertEquals(prepared.snapshot.idempotencyKey, ledger.activeIntents("acct-demo").single().idempotencyKey)
  }

  @Test
  fun testCreatedIntentIsReplaced() {
    val (_, ledger) = ledger()
    val created = ledger.begin("acct-demo", "northline-studio", 2599, "card", "Studio invoice", "success")
    val replacement = ledger.begin("acct-demo", "northline-studio", 100, "bank", "other", "success")
    assertNotEquals(created.snapshot.paymentIntentId, replacement.snapshot.paymentIntentId)
    assertNotEquals(created.snapshot.idempotencyKey, replacement.snapshot.idempotencyKey)
    val active = ledger.activeIntents("acct-demo")
    assertEquals(1, active.size)
    assertEquals(replacement.snapshot.paymentIntentId, active[0].paymentIntentId)
    val cancelled = ledger.snapshots("acct-demo").first { it.paymentIntentId == created.snapshot.paymentIntentId }
    assertEquals(PaymentIntentStatus.cancelled, cancelled.status)
  }

  @Test
  fun testReturnStateVerification() {
    val (_, ledger) = ledger()
    val prepared = ledger.begin("acct-demo", "northline-studio", 2599, "card", "Studio invoice", "success")
    assertTrue(ledger.verifyReturnState(prepared.snapshot, prepared.returnState!!))
    assertFalse(ledger.verifyReturnState(prepared.snapshot, "different-return-state"))
    assertFalse(prepared.snapshot.returnStateHash == prepared.returnState)
  }

  @Test
  fun testSnapshotJsonRoundTrip() {
    val (_, ledger) = ledger()
    val prepared = ledger.begin("acct-demo", "northline-studio", 2599, "card", "Studio invoice", "success")
    val json = mapper.writeValueAsString(prepared.snapshot)
    val restored = mapper.readValue(json, PaymentIntentSnapshot::class.java)
    assertEquals(prepared.snapshot, restored)
    assertEquals(prepared.snapshot.paymentIntentId, restored.paymentIntentId)
    assertEquals(prepared.snapshot.idempotencyKey, restored.idempotencyKey)
    assertEquals(prepared.snapshot.businessPayloadHash, restored.businessPayloadHash)
    assertEquals(PaymentIntentStatus.created, restored.status)
    assertEquals(prepared.snapshot.returnStateHash, restored.returnStateHash)
  }

  @Test
  fun testDeclineAllowsNewIntent() {
    val (_, ledger) = ledger()
    val prepared = ledger.begin("acct-demo", "northline-studio", 2599, "card", "Studio invoice", "success")
    ledger.markSubmitted("acct-demo", prepared.snapshot.paymentIntentId)
    val declined = ledger.record(
      PaymentResponse(ok = false, code = "INSUFFICIENT_BALANCE", error = "Insufficient balance"),
      "acct-demo",
      prepared.snapshot.paymentIntentId,
    )
    assertEquals(PaymentIntentStatus.declined, declined.status)
    assertTrue(declined.status.isTerminal)
    assertTrue(ledger.activeIntents("acct-demo").isEmpty())
    val next = ledger.begin("acct-demo", "northline-studio", 100, "card", "Studio invoice", "success")
    assertNotEquals(prepared.snapshot.idempotencyKey, next.snapshot.idempotencyKey)
    assertEquals(PaymentIntentStatus.created, ledger.activeIntents("acct-demo").single().status)
  }

  @Test
  fun testStorageKeyIsAccountScoped() {
    val key = PaymentIntentStorageKeys.snapshotKey("acct-demo", "pi_storage_key")
    assertEquals("acct-demo|pi_storage_key", key)
    assertTrue(PaymentIntentStorageKeys.belongsToAccount(key, "acct-demo"))
    assertFalse(PaymentIntentStorageKeys.belongsToAccount(key, "acct"))
    assertFalse(PaymentIntentStorageKeys.belongsToAccount(key, "other-acct"))
  }

  private class Clock(var now: Long = 5_000L)

  private fun ledger(
    clock: Clock = Clock(),
    retentionMillis: Long = PaymentIntentRetention.TERMINAL_WINDOW_MILLIS,
  ): Pair<InMemoryPaymentIntentStore, PaymentIntentLedger> {
    val store = InMemoryPaymentIntentStore()
    return store to PaymentIntentLedger(store, nowMillis = { clock.now }, retentionMillis = retentionMillis)
  }
}
