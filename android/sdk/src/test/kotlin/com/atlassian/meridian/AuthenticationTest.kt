package com.atlassian.meridian

import org.junit.Assert.*
import org.junit.Test

class AuthenticationTest {
  private val payload =
    """{"exp":1700000300,"nonce":"11111111-1111-1111-1111-111111111111","paymentKey":"pay-key-1","session":"meridian-rehearsal","v":1}"""
  private val knownToken =
    "eyJleHAiOjE3MDAwMDAzMDAsIm5vbmNlIjoiMTExMTExMTEtMTExMS0xMTExLTExMTEtMTExMTExMTExMTExIiwicGF5bWVudEtleSI6InBheS1rZXktMSIsInNlc3Npb24iOiJtZXJpZGlhbi1yZWhlYXJzYWwiLCJ2IjoxfQ.668b20e0e5b693d0d4f4abfe251d61c9616b79941849d3224eb8fc5b17b88acb"

  @Test
  fun testHmacSha256Rfc4231() {
    val key = ByteArray(20) { 0x0b }
    val mac = ReturnStateVault.hmacSha256(key, "Hi There".toByteArray())
    assertEquals("b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7", hex(mac))
  }

  @Test
  fun testKnownSignedReturnToken() {
    val token = ReturnStateVault.sign("rehearsal-test-key".toByteArray(), payload)
    assertEquals(knownToken, token)
    val vault = ReturnStateVault(key = "rehearsal-test-key".toByteArray(), now = { 1_700_000_000 })
    val decision = vault.intercept(returnUrl(token), "meridian-rehearsal", "pay-key-1")
    assertEquals(ReturnOutcome.accepted, decision.outcome)
    assertTrue(decision.allowsPaymentSubmit)
    assertFalse(decision.createsPayment)
    assertEquals("pay-key-1", decision.idempotencyKey)
  }

  @Test
  fun testAllowlistedHandoffOnly() {
    val token = knownToken
    val handoff = "https://bank.meridian-rehearsal.test/handoff?state=$token"
    assertTrue(BankHandoffPolicy.inspectBankHandoff(handoff) is UrlCheck.Allowed)
    assertTrue(BankHandoffPolicy.inspectBankHandoff("http://bank.meridian-rehearsal.test/handoff?state=$token") is UrlCheck.Refused)
    assertTrue(BankHandoffPolicy.inspectBankHandoff("https://user:secret@bank.meridian-rehearsal.test/handoff?state=$token") is UrlCheck.Refused)
    assertTrue(BankHandoffPolicy.inspectBankHandoff("https://bank.meridian-rehearsal.test.evil.example/handoff?state=$token") is UrlCheck.Refused)
    assertTrue(BankHandoffPolicy.inspectBankHandoff("https://online.worldpay.com/handoff?state=$token") is UrlCheck.Refused)
    assertTrue(BankHandoffPolicy.inspectBankHandoff("https://checkoutshopper-live.adyen.com/checkout?state=$token") is UrlCheck.Refused)
    assertTrue(BankHandoffPolicy.inspectBankHandoff("$handoff&amountMinor=100") is UrlCheck.Refused)
    assertTrue(BankHandoffPolicy.inspectBankHandoff("$handoff#fragment") is UrlCheck.Refused)
  }

  @Test
  fun testIssuedHandoffCarriesOnlyOpaqueState() {
    val vault = ReturnStateVault(key = "rehearsal-test-key".toByteArray(), now = { 1_700_000_000 })
    val issued = vault.issue("meridian-rehearsal", "pay-key-1")
    assertTrue(issued.handoffUrl.startsWith("https://bank.meridian-rehearsal.test/handoff?state="))
    assertFalse(issued.handoffUrl.contains("amount"))
    assertFalse(issued.handoffUrl.contains("recipient"))
    assertFalse(issued.handoffUrl.contains("pay-key-1"))
    assertEquals("pay-key-1", issued.idempotencyKey)
    val decision = vault.intercept(issued.returnUrl, "meridian-rehearsal", "pay-key-1")
    assertEquals(ReturnOutcome.accepted, decision.outcome)
  }

  @Test
  fun testTamperedTokenDoesNotSubmit() {
    val vault = ReturnStateVault(key = "rehearsal-test-key".toByteArray(), now = { 1_700_000_000 })
    val tampered = knownToken.dropLast(1) + "0"
    val decision = vault.intercept(returnUrl(tampered), "meridian-rehearsal", "pay-key-1")
    assertEquals(ReturnOutcome.invalid, decision.outcome)
    assertFalse(decision.allowsPaymentSubmit)
    assertFalse(decision.createsPayment)
    assertNothingSubmitted(PaymentAttempt("pay-key-1", PaymentMethod.bank).applying(decision))
  }

  @Test
  fun testExpiredTokenDoesNotSubmit() {
    val vault = ReturnStateVault(key = "rehearsal-test-key".toByteArray(), now = { 1_700_000_300 })
    val decision = vault.intercept(returnUrl(knownToken), "meridian-rehearsal", "pay-key-1")
    assertEquals(ReturnOutcome.expired, decision.outcome)
    assertFalse(decision.allowsPaymentSubmit)
    assertNothingSubmitted(PaymentAttempt("pay-key-1", PaymentMethod.bank).applying(decision))
  }

  @Test
  fun testReplayedTokenDoesNotSubmitAgain() {
    val vault = ReturnStateVault(key = "rehearsal-test-key".toByteArray(), now = { 1_700_000_000 })
    val url = returnUrl(knownToken)
    val first = vault.intercept(url, "meridian-rehearsal", "pay-key-1")
    val second = vault.intercept(url, "meridian-rehearsal", "pay-key-1")
    assertEquals(ReturnOutcome.accepted, first.outcome)
    assertEquals(ReturnOutcome.replayed, second.outcome)
    assertFalse(second.allowsPaymentSubmit)
    assertFalse(second.createsPayment)
    assertEquals("pay-key-1", second.idempotencyKey)
    var calls = 0
    val attempt = PaymentAttempt("pay-key-1", PaymentMethod.bank).applying(second)
    assertFalse(attempt.submitIfReady { calls += 1 })
    assertEquals(0, calls)
  }

  @Test
  fun testForeignPaymentKeyIsNotAdopted() {
    val vault = ReturnStateVault(key = "rehearsal-test-key".toByteArray(), now = { 1_700_000_000 })
    val decision = vault.intercept(returnUrl(knownToken), "meridian-rehearsal", "other-key")
    assertEquals(ReturnOutcome.invalid, decision.outcome)
    assertEquals("other-key", decision.idempotencyKey)
    assertFalse(decision.allowsPaymentSubmit)
    assertNothingSubmitted(PaymentAttempt("other-key", PaymentMethod.bank).applying(decision))
  }

  @Test
  fun testUnrelatedLinkIsIgnored() {
    val vault = ReturnStateVault(key = "rehearsal-test-key".toByteArray(), now = { 1_700_000_000 })
    val decision = vault.intercept("https://example.test/elsewhere", "meridian-rehearsal", "pay-key-1")
    assertEquals(ReturnOutcome.ignored, decision.outcome)
    assertFalse(decision.allowsPaymentSubmit)
    assertFalse(decision.createsPayment)
  }

  @Test
  fun testCancelledReturnCannotCreatePayment() {
    val vault = ReturnStateVault(key = "rehearsal-test-key".toByteArray(), now = { 1_700_000_000 })
    vault.cancel(knownToken)
    val decision = vault.intercept(returnUrl(knownToken), "meridian-rehearsal", "pay-key-1")
    assertEquals(ReturnOutcome.replayed, decision.outcome)
    assertNothingSubmitted(PaymentAttempt("pay-key-1", PaymentMethod.bank).applying(decision))
  }

  @Test
  fun testCardPinAndBiometricGate() {
    val original = "payment-key-42"
    var attempt = PaymentAttempt(original, PaymentMethod.card)
    assertFalse(attempt.submitIfReady { error("must not submit") })

    val (mismatched, mismatch) = attempt.confirmingPin("1234", "9999")
    assertEquals("PIN entries do not match", mismatch)
    assertFalse(mismatched.readyToSubmit)
    assertEquals(original, mismatched.idempotencyKey)

    val (short, shortError) = attempt.confirmingPin("12", "12")
    assertEquals("PIN must be 4 to 6 digits", shortError)
    assertFalse(short.readyToSubmit)

    val denied = attempt.confirmingBiometric(false)
    assertFalse(denied.submitIfReady { error("biometric failure must not submit") })

    val confirmed = attempt.confirmingPin("1234", "1234").first
    assertTrue(confirmed.scaConfirmed)
    var used: String? = null
    assertTrue(confirmed.submitIfReady { used = it })
    assertEquals(original, used)

    val biometric = attempt.confirmingBiometric(true)
    used = null
    assertTrue(biometric.submitIfReady { used = it })
    assertEquals(original, used)
  }

  @Test
  fun testBankStaysBlockedUntilFreshReturn() {
    val key = "pay-key-1"
    val vault = ReturnStateVault(key = "rehearsal-test-key".toByteArray(), now = { 1_700_000_000 })
    val attempt = PaymentAttempt(key, PaymentMethod.bank)
    assertFalse(attempt.readyToSubmit)
    assertFalse(attempt.submitIfReady { error("handoff is not authentication") })
    val decision = vault.intercept(returnUrl(knownToken), "meridian-rehearsal", key)
    val ready = attempt.applying(decision)
    var used: String? = null
    assertTrue(ready.submitIfReady { used = it })
    assertEquals(key, used)
    assertEquals(1, setOf(key).size)
  }

  private fun returnUrl(token: String) =
    "https://app.meridian-rehearsal.test/bank/return?state=$token"

  private fun assertNothingSubmitted(attempt: PaymentAttempt) {
    assertFalse(attempt.readyToSubmit)
    assertFalse(attempt.submitIfReady { error("payment must not be created") })
    assertFalse(attempt.idempotencyKey.isEmpty())
  }
}
