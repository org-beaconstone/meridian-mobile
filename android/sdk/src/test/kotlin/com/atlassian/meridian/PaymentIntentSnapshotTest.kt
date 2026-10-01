package com.atlassian.meridian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PaymentIntentSnapshotTest {
  private val window = PaymentIntentRetention.TERMINAL_WINDOW_MS

  @Test
  fun testBusinessPayloadHashVector() {
    val hash = businessPayloadHash("acct-1", "northline-studio", 2599, PaymentMethod.card, "lunch")
    assertEquals("f7005a22f7deb113825ad2d2ec98e98abbd62f06fde119402dd062575bd863a6", hash)
  }

  @Test
  fun testBusinessPayloadHashEscapesNote() {
    val hash = businessPayloadHash("acct-1", "northline-studio", 100, PaymentMethod.bank, "say \"hi\"")
    assertEquals("311d46ff743ceab3f78257a3b6313cf311f234079de3c0c32845de6266d978ef", hash)
    assertFalse(hash == businessPayloadHash("acct-1", "northline-studio", 101, PaymentMethod.bank, "say \"hi\""))
  }

  @Test
  fun testReturnStateHashVectors() {
    val settled = returnStateHash(
      PaymentReturnState(ok = true, paymentId = "pay-1", stateVersion = 4, balancePence = 1_245_451),
    )
    assertEquals("b5249909bae8e7dd177a9d782f43300fb7e0ce1da42a696d0f5770227d68bb44", settled)
    val pending = returnStateHash(
      PaymentReturnState(
        ok = false,
        paymentId = "pay-9",
        code = "PAYMENT_PENDING",
        error = "Awaiting confirmation",
      ),
    )
    assertEquals("a5ea41d10b6f195c073b33f96c57bb76cfee49de91d4a38c5220bd4ecb85197b", pending)
  }

  @Test
  fun testStatusMapping() {
    assertEquals(PaymentIntentStatus.succeeded, paymentIntentStatus(PaymentResponse(ok = true, paymentId = "pay-1")))
    assertEquals(
      PaymentIntentStatus.pending,
      paymentIntentStatus(PaymentResponse(ok = false, code = "PAYMENT_PENDING", paymentId = "pay-9")),
    )
    assertEquals(
      PaymentIntentStatus.declined,
      paymentIntentStatus(PaymentResponse(ok = false, code = "PAYMENT_DECLINED")),
    )
    assertEquals(
      PaymentIntentStatus.processing,
      paymentIntentStatus(PaymentResponse(ok = false, code = "PROVIDER_UNAVAILABLE")),
    )
    assertEquals(
      PaymentIntentStatus.processing,
      paymentIntentStatus(PaymentResponse(ok = false)),
    )
    assertEquals(
      PaymentIntentStatus.failed,
      paymentIntentStatus(PaymentResponse(ok = false, code = "VALIDATION_ERROR")),
    )
  }

  @Test
  fun testSnapshotRecordsRequiredFieldsAndIsolatesAccounts() {
    val repository = PaymentIntentSnapshotRepository(InMemoryPaymentIntentSnapshotStore())
    val began = repository.begin(draft(account = "acct-a", intent = "intent-aaa1", key = "idem-key-a1"), nowEpochMs = 1_000)
    assertTrue(began.created)
    assertTrue(began.payloadMatches)
    val snapshot = began.snapshot
    assertEquals("intent-aaa1", snapshot.paymentIntentId)
    assertEquals("idem-key-a1", snapshot.idempotencyKey)
    assertEquals(
      businessPayloadHash("acct-a", "northline-studio", 2599, PaymentMethod.card, "lunch"),
      snapshot.businessPayloadHash,
    )
    assertEquals(PaymentIntentStatus.processing, snapshot.status)
    assertNull(snapshot.returnState)
    assertNull(snapshot.returnStateHash)
    assertTrue(repository.resumeActive("acct-b", 1_000).isEmpty())
    assertNull(repository.load("acct-b", "intent-aaa1", 1_000))
  }

  @Test
  fun testProcessRecoveryReusesIdempotencyKey() {
    val store = InMemoryPaymentIntentSnapshotStore()
    val started = PaymentIntentSnapshotRepository(store)
      .begin(draft(account = "acct-a", intent = "intent-aaa1", key = "idem-key-a1"), nowEpochMs = 5_000)
    val recovered = PaymentIntentSnapshotRepository(store).resumeActive("acct-a", 9_000)
    assertEquals(1, recovered.size)
    assertEquals(started.snapshot.paymentIntentId, recovered[0].paymentIntentId)
    assertEquals("idem-key-a1", recovered[0].idempotencyKey)
    assertEquals(started.snapshot.businessPayloadHash, recovered[0].businessPayloadHash)
    assertFalse(recovered[0].status.isTerminal)
  }

  @Test
  fun testUncertainOutcomeStaysResumable() {
    val repository = PaymentIntentSnapshotRepository(InMemoryPaymentIntentSnapshotStore())
    val began = repository.begin(draft(account = "acct-a", intent = "intent-aaa1", key = "idem-key-a1"), nowEpochMs = 10)
    val uncertain = repository.markUncertain("acct-a", began.snapshot.paymentIntentId, 20)
    assertEquals(PaymentIntentStatus.processing, uncertain.status)
    assertEquals("idem-key-a1", uncertain.idempotencyKey)
    val again = repository.begin(
      draft(account = "acct-a", intent = "intent-bbb2", key = "idem-key-b2"),
      nowEpochMs = 30,
    )
    assertFalse(again.created)
    assertTrue(again.payloadMatches)
    assertEquals("idem-key-a1", again.snapshot.idempotencyKey)
  }

  @Test
  fun testDifferentPayloadDoesNotReplaceActiveIntent() {
    val repository = PaymentIntentSnapshotRepository(InMemoryPaymentIntentSnapshotStore())
    repository.begin(draft(account = "acct-a", intent = "intent-aaa1", key = "idem-key-a1"), nowEpochMs = 10)
    val other = repository.begin(
      draft(account = "acct-a", intent = "intent-bbb2", key = "idem-key-b2", amount = 2600),
      nowEpochMs = 11,
    )
    assertFalse(other.created)
    assertFalse(other.payloadMatches)
    assertEquals("idem-key-a1", other.snapshot.idempotencyKey)
    assertEquals(2599, other.snapshot.amountMinor)
  }

  @Test
  fun testTerminalRetentionWindow() {
    val repository = PaymentIntentSnapshotRepository(InMemoryPaymentIntentSnapshotStore())
    val began = repository.begin(draft(account = "acct-a", intent = "intent-aaa1", key = "idem-key-a1"), nowEpochMs = 1_000)
    val done = repository.recordOutcome(
      "acct-a",
      began.snapshot.paymentIntentId,
      PaymentResponse(
        ok = true,
        paymentId = "pay-1",
        state = BankState(version = 4, balance = 1_245_451, transactions = emptyList(), budgets = emptyList()),
      ),
      2_000,
    )
    assertEquals(PaymentIntentStatus.succeeded, done.status)
    assertEquals("b5249909bae8e7dd177a9d782f43300fb7e0ce1da42a696d0f5770227d68bb44", done.returnStateHash)
    assertEquals("pay-1", done.returnState?.paymentId)
    assertEquals(1_245_451, done.returnState?.balancePence)
    assertTrue(repository.resumeActive("acct-a", 2_000).isEmpty())
    assertNotNull(repository.load("acct-a", began.snapshot.paymentIntentId, 2_000 + window - 1))
    assertEquals(0, repository.purgeExpired("acct-a", 2_000 + window - 1))
    assertNull(repository.load("acct-a", began.snapshot.paymentIntentId, 2_000 + window))
    assertEquals(0, repository.purgeExpired("acct-a", 2_000 + window))
  }

  @Test
  fun testActiveIntentDoesNotExpireWithAge() {
    val repository = PaymentIntentSnapshotRepository(InMemoryPaymentIntentSnapshotStore())
    repository.begin(draft(account = "acct-a", intent = "intent-aaa1", key = "idem-key-a1"), nowEpochMs = 1_000)
    val later = 1_000 + window * 5
    val active = repository.resumeActive("acct-a", later)
    assertEquals(1, active.size)
    assertEquals("idem-key-a1", active[0].idempotencyKey)
  }

  @Test
  fun testPendingKeepsKeyThenSuccessExpiresLater() {
    val repository = PaymentIntentSnapshotRepository(InMemoryPaymentIntentSnapshotStore())
    val began = repository.begin(draft(account = "acct-a", intent = "intent-aaa1", key = "idem-key-a1"), nowEpochMs = 50)
    val pending = repository.recordOutcome(
      "acct-a",
      began.snapshot.paymentIntentId,
      PaymentResponse(ok = false, code = "PAYMENT_PENDING", error = "Awaiting confirmation", paymentId = "pay-9"),
      60,
    )
    assertEquals(PaymentIntentStatus.pending, pending.status)
    assertEquals("a5ea41d10b6f195c073b33f96c57bb76cfee49de91d4a38c5220bd4ecb85197b", pending.returnStateHash)
    assertEquals("idem-key-a1", repository.resumeActive("acct-a", 70).single().idempotencyKey)
    val settled = repository.recordOutcome(
      "acct-a",
      began.snapshot.paymentIntentId,
      PaymentResponse(ok = true, paymentId = "pay-9"),
      80,
    )
    assertEquals(PaymentIntentStatus.succeeded, settled.status)
    assertEquals(80L, settled.terminalAtEpochMs)
    assertTrue(repository.resumeActive("acct-a", 80).isEmpty())
  }

  @Test
  fun testCancelIsTerminalUntilRetentionEnds() {
    val repository = PaymentIntentSnapshotRepository(InMemoryPaymentIntentSnapshotStore())
    val began = repository.begin(draft(account = "acct-a", intent = "intent-aaa1", key = "idem-key-a1"), nowEpochMs = 10)
    val cancelled = repository.cancel("acct-a", began.snapshot.paymentIntentId, 40)
    assertEquals(PaymentIntentStatus.cancelled, cancelled?.status)
    assertTrue(repository.resumeActive("acct-a", 40).isEmpty())
    assertNotNull(repository.load("acct-a", "intent-aaa1", 40 + window - 1))
    assertNull(repository.load("acct-a", "intent-aaa1", 40 + window))
    val replacement = repository.begin(
      draft(account = "acct-a", intent = "intent-ccc3", key = "idem-key-c3"),
      nowEpochMs = 41,
    )
    assertTrue(replacement.created)
    assertEquals("idem-key-c3", replacement.snapshot.idempotencyKey)
  }

  @Test
  fun testEncryptedPreferenceLayoutRestoresAfterNewRepository() {
    val files = MemorySecurePreferenceFiles()
    val original = PaymentIntentSnapshotRepository(PreferencePaymentIntentSnapshotStore(files))
    val began = original.begin(draft(account = "acct-a", intent = "intent-aaa1", key = "idem-key-a1"), nowEpochMs = 15)
    original.recordOutcome(
      "acct-a",
      began.snapshot.paymentIntentId,
      PaymentResponse(ok = false, code = "PAYMENT_PENDING", error = "Awaiting confirmation", paymentId = "pay-9"),
      16,
    )
    val recovered = PaymentIntentSnapshotRepository(PreferencePaymentIntentSnapshotStore(files))
    val active = recovered.resumeActive("acct-a", 17)
    assertEquals(1, active.size)
    assertEquals("intent-aaa1", active[0].paymentIntentId)
    assertEquals("idem-key-a1", active[0].idempotencyKey)
    assertEquals("pay-9", active[0].returnState?.paymentId)
    assertEquals(
      "a5ea41d10b6f195c073b33f96c57bb76cfee49de91d4a38c5220bd4ecb85197b",
      active[0].returnStateHash,
    )
    assertTrue(recovered.resumeActive("acct-b", 17).isEmpty())
    assertNull(recovered.load("acct-b", "intent-aaa1", 17))
    val stored = files.fileFor("acct-a").get("intent-aaa1")
    assertNotNull(stored)
    assertTrue(stored!!.contains("idem-key-a1"))
    assertTrue(stored.contains("businessPayloadHash"))
  }

  @Test
  fun testAccountFilesDoNotOverlap() {
    val files = MemorySecurePreferenceFiles()
    val repository = PaymentIntentSnapshotRepository(PreferencePaymentIntentSnapshotStore(files))
    repository.begin(draft(account = "acct-a", intent = "intent-aaa1", key = "idem-key-a1"), nowEpochMs = 1)
    repository.begin(draft(account = "acct-b", intent = "intent-bbb2", key = "idem-key-b2", amount = 100), nowEpochMs = 1)
    assertEquals("idem-key-a1", repository.resumeActive("acct-a", 2).single().idempotencyKey)
    assertEquals("idem-key-b2", repository.resumeActive("acct-b", 2).single().idempotencyKey)
    assertFalse(accountStorageKey("acct-a") == accountStorageKey("acct-b"))
  }

  @Test(expected = SnapshotError::class)
  fun testRejectsEmptyCustomerAccount() {
    PaymentIntentSnapshotRepository(InMemoryPaymentIntentSnapshotStore())
      .begin(draft(account = "", intent = "intent-aaa1", key = "idem-key-a1"), nowEpochMs = 1)
  }

  private fun draft(
    account: String,
    intent: String,
    key: String,
    amount: Int = 2599,
  ) = PaymentIntentDraft(
    customerAccountId = account,
    paymentIntentId = intent,
    idempotencyKey = key,
    recipientId = "northline-studio",
    amountMinor = amount,
    method = PaymentMethod.card,
    note = "lunch",
  )
}
