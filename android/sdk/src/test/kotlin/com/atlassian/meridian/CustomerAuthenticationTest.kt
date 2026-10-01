package com.atlassian.meridian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.SecureRandom

class CustomerAuthenticationTest {
  private val binding = "idempotency-key-do-not-leak"
  private val secret = ByteArray(32) { 7 }

  @Test
  fun base64UrlRoundTripBoundaries() {
    assertEquals("Zg", base64UrlEncode(byteArrayOf(0x66)))
    assertEquals("Zm8", base64UrlEncode(byteArrayOf(0x66, 0x6f)))
    assertEquals("Zm9v", base64UrlEncode(byteArrayOf(0x66, 0x6f, 0x6f)))
    assertEquals(0x66.toByte(), base64UrlDecode("Zg")!!.single())
    val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
    assertTrue(base64UrlDecode(base64UrlEncode(bytes))!!.contentEquals(bytes))
    assertNull(base64UrlDecode("ab+d"))
    assertNull(base64UrlDecode("abcde"))
  }

  @Test
  fun issuedStateIsOpaqueAndValidForItsBinding() {
    val signer = signer()
    val token = signer.issue(binding)
    assertFalse(token.contains(binding))
    assertFalse(token.contains("northline"))
    assertFalse(token.contains("2599"))
    assertFalse(token.contains("adyen"))
    assertTrue(signer.validate(token, binding) is ReturnStatus.Accepted)
  }

  @Test
  fun tamperedSignatureOrBindingIsInvalidAndDoesNotConsume() {
    val signer = signer()
    val token = signer.issue(binding)
    val parts = token.split('.')
    val signature = parts[3]
    val flipped = if (signature.first() == 'A') 'B' else 'A'
    val tampered = "${parts[0]}.${parts[1]}.${parts[2]}.$flipped${signature.drop(1)}"
    assertEquals(ReturnFailure.invalid, (signer.validate(tampered, binding) as ReturnStatus.Rejected).reason)
    assertEquals(ReturnFailure.invalid, (signer.validate(token, "other-binding") as ReturnStatus.Rejected).reason)
    assertTrue(signer.validate(token, binding) is ReturnStatus.Accepted)
  }

  @Test
  fun expiredReturnIsRejectedAndCanBePresentedAgainAsExpired() {
    val clock = longArrayOf(1_700_000_000L)
    val signer = ReturnStateSigner(secret, ttlSeconds = 300, clock = { clock[0] }, random = { count -> ByteArray(count) { 9 } })
    val token = signer.issue(binding)
    clock[0] = 1_700_000_000L + 300
    assertEquals(ReturnFailure.expired, (signer.validate(token, binding) as ReturnStatus.Rejected).reason)
    assertEquals(ReturnFailure.expired, (signer.validate(token, binding) as ReturnStatus.Rejected).reason)
  }

  @Test
  fun acceptedReturnIsSingleUse() {
    val signer = signer()
    val token = signer.issue(binding)
    assertTrue(signer.validate(token, binding) is ReturnStatus.Accepted)
    assertEquals(ReturnFailure.replayed, (signer.validate(token, binding) as ReturnStatus.Rejected).reason)
  }

  @Test
  fun handoffUrlStaysOnTheAllowlistedHttpsHost() {
    val url = BankAllowlist.handoffUrl("v1.nonce.1700000300.sig")!!
    assertTrue(url.startsWith("https://bank.worldpay.rehearsal.meridian.example/open-banking/authorize?"))
    assertTrue(BankAllowlist.permitsHandoff(url))
    assertFalse(url.contains(binding))
    val state = stateToken(url)
    assertEquals("v1.nonce.1700000300.sig", state)
    val intercept = BankAllowlist.intercept(BankAllowlist.returnUrl(state)!!)
    assertEquals(state, (intercept as ReturnIntercept.Token).token)
  }

  @Test
  fun disallowedBankUrlsAreNotOpened() {
    val blocked = listOf(
      "http://bank.worldpay.rehearsal.meridian.example/open-banking/authorize?state=abc&redirect_uri=https%3A%2F%2Fapp.meridian.example%2Fbank%2Freturn",
      "https://user:pass@bank.worldpay.rehearsal.meridian.example/open-banking/authorize?state=abc&redirect_uri=https%3A%2F%2Fapp.meridian.example%2Fbank%2Freturn",
      "https://bank.worldpay.rehearsal.meridian.example.evil.com/open-banking/authorize?state=abc&redirect_uri=https%3A%2F%2Fapp.meridian.example%2Fbank%2Freturn",
      "https://evil.example/open-banking/authorize?state=abc&redirect_uri=https%3A%2F%2Fapp.meridian.example%2Fbank%2Freturn",
      "https://bank.worldpay.rehearsal.meridian.example:8443/open-banking/authorize?state=abc&redirect_uri=https%3A%2F%2Fapp.meridian.example%2Fbank%2Freturn",
      "https://bank.worldpay.rehearsal.meridian.example/open-banking/authorize?state=abc&redirect_uri=https%3A%2F%2Fevil.example%2Fbank%2Freturn",
    )
    blocked.forEach { url ->
      var opened = 0
      assertFalse(url, BankAllowlist.openIfAllowlisted(url) { opened += 1; true })
      assertEquals(url, 0, opened)
    }
  }

  @Test
  fun returnListenerAcceptsOnlyTheAppLink() {
    val token = "v1.nonce.1700000300.sig"
    val link = BankAllowlist.returnUrl(token)!!
    assertEquals(token, (BankAllowlist.intercept(link) as ReturnIntercept.Token).token)
    assertEquals(token, (BankAllowlist.intercept(link.replace("/bank/return?", "/bank/return/?")) as ReturnIntercept.Token).token)
    assertTrue(BankAllowlist.intercept("https://app.meridian.example/bank/return") is ReturnIntercept.MissingState)
    assertTrue(BankAllowlist.intercept("https://evil.example/bank/return?state=$token") is ReturnIntercept.NotReturnLink)
    assertTrue(BankAllowlist.intercept("http://app.meridian.example/bank/return?state=$token") is ReturnIntercept.NotReturnLink)
    assertTrue(BankAllowlist.intercept("https://app.meridian.example/elsewhere?state=$token") is ReturnIntercept.NotReturnLink)
  }

  @Test
  fun invalidExpiredAndReplayedReturnsDoNotSubmitOrRotateTheKey() {
    val clock = longArrayOf(1_700_000_000L)
    val signer = ReturnStateSigner(secret, clock = { clock[0] })
    val attempt = PaymentAttempt(binding, PaymentMethod.bank, signer, "135790")
    val opened = attempt.startHandoff { true }!!
    val returnUrl = BankAllowlist.returnUrl(stateToken(opened))!!
    val submitted = mutableListOf<String>()

    val missing = attempt.resumeAfterReturn("https://app.meridian.example/bank/return") { submitted += it }
    assertEquals(ReturnFailure.missing, (missing as ReturnOutcome.SafeFailure).reason)
    assertEquals(binding, missing.idempotencyKey)

    val invalid = attempt.resumeAfterReturn("https://app.meridian.example/bank/return?state=v1.bad.1.bad") { submitted += it }
    assertEquals(ReturnFailure.invalid, (invalid as ReturnOutcome.SafeFailure).reason)

    clock[0] = 1_700_000_000L + 301
    val expired = attempt.resumeAfterReturn(returnUrl) { submitted += it }
    assertEquals(ReturnFailure.expired, (expired as ReturnOutcome.SafeFailure).reason)
    assertEquals(0, submitted.size)
    assertEquals(binding, attempt.idempotencyKey)
    assertEquals(PaymentMethod.bank, attempt.method)
    assertFalse(attempt.submitIfCleared { submitted += it })

    clock[0] = 1_700_000_000L
    val fresh = PaymentAttempt(binding, PaymentMethod.bank, signer(), "135790")
    val liveUrl = BankAllowlist.returnUrl(stateToken(fresh.startHandoff { true }!!))!!
    assertTrue(fresh.resumeAfterReturn(liveUrl) { submitted += it } is ReturnOutcome.Cleared)
    val replay = fresh.resumeAfterReturn(liveUrl) { submitted += it }
    assertEquals(ReturnFailure.replayed, (replay as ReturnOutcome.SafeFailure).reason)
    assertEquals(listOf(binding), submitted)
    assertEquals(binding, fresh.idempotencyKey)
  }

  @Test
  fun supersededReturnCannotCreateASecondPayment() {
    val attempt = PaymentAttempt(binding, PaymentMethod.bank, signer(), "")
    val first = attempt.startHandoff { true }!!
    val second = attempt.startHandoff { true }!!
    assertNotEquals(first, second)
    val submitted = mutableListOf<String>()
    val stale = attempt.resumeAfterReturn(BankAllowlist.returnUrl(stateToken(first))!!) { submitted += it }
    assertTrue(stale is ReturnOutcome.SafeFailure)
    assertEquals(0, submitted.size)
    val current = attempt.resumeAfterReturn(BankAllowlist.returnUrl(stateToken(second))!!) { submitted += it }
    assertEquals(binding, (current as ReturnOutcome.Cleared).idempotencyKey)
    assertEquals(listOf(binding), submitted)
    assertEquals(PaymentMethod.bank, attempt.method)
  }

  @Test
  fun openerRefusalDoesNotArmAReturn() {
    val attempt = PaymentAttempt(binding, PaymentMethod.bank, signer(), "")
    var opened = 0
    assertNull(attempt.startHandoff { opened += 1; false })
    assertEquals(1, opened)
    assertNull(attempt.rehearsalReturnUrl())
    var submitted = 0
    assertFalse(attempt.submitIfCleared { submitted += 1 })
    assertEquals(0, submitted)
  }

  @Test
  fun cardPaymentRequiresBiometricOrPinAndDoesNotOpenABank() {
    val attempt = PaymentAttempt(binding, PaymentMethod.card, signer(), "135790")
    var opened = 0
    var submitted = mutableListOf<String>()
    assertNull(attempt.startHandoff { opened += 1; true })
    assertEquals(0, opened)
    assertFalse(attempt.submitIfCleared { submitted += it })

    val rejected = attempt.resumeAfterSca(false, "") { submitted += it }
    assertTrue(rejected is ScaDecision.Rejected)
    val wrongPin = attempt.resumeAfterSca(false, "135791") { submitted += it }
    assertTrue(wrongPin is ScaDecision.Rejected)
    val shortPin = PaymentAttempt(binding, PaymentMethod.card, signer(), "123")
    assertTrue(shortPin.resumeAfterSca(false, "123") { submitted += it } is ScaDecision.Rejected)
    assertEquals(0, submitted.size)
    assertEquals(binding, attempt.idempotencyKey)

    val biometric = attempt.resumeAfterSca(true, "") { submitted += it }
    assertEquals(ScaFactor.biometric, (biometric as ScaDecision.Confirmed).factor)
    val secondTap = attempt.resumeAfterSca(true, "") { submitted += it }
    assertEquals(ScaFactor.biometric, (secondTap as ScaDecision.Confirmed).factor)
    assertEquals(listOf(binding), submitted)

    val pinAttempt = PaymentAttempt(binding, PaymentMethod.card, signer(), "135790")
    val pin = pinAttempt.resumeAfterSca(false, "135790") { submitted += it }
    assertEquals(ScaFactor.pin, (pin as ScaDecision.Confirmed).factor)
    assertEquals(listOf(binding, binding), submitted)
  }

  @Test
  fun uncertainRetryKeepsTheSameKeyAfterRelease() {
    val attempt = PaymentAttempt(binding, PaymentMethod.card, signer(), "135790")
    val keys = mutableListOf<String>()
    attempt.resumeAfterSca(true, "") { keys += it }
    attempt.releaseForRetry()
    assertTrue(attempt.canRetry)
    assertTrue(attempt.submitIfCleared { keys += it })
    assertEquals(listOf(binding, binding), keys)
    attempt.markCompleted()
    assertFalse(attempt.submitIfCleared { keys += it })
    assertEquals(2, keys.size)
  }

  @Test
  fun bankReturnDoesNotClearThroughSca() {
    val attempt = PaymentAttempt(binding, PaymentMethod.bank, signer(), "135790")
    var submitted = 0
    assertTrue(attempt.resumeAfterSca(true, "135790") { submitted += 1 } is ScaDecision.NotRequired)
    assertEquals(0, submitted)
    assertEquals(PaymentMethod.bank, attempt.method)
  }

  @Test
  fun ignoredLinkDoesNotSubmit() {
    val attempt = PaymentAttempt(binding, PaymentMethod.bank, signer(), "")
    attempt.startHandoff { true }
    var submitted = 0
    assertTrue(attempt.resumeAfterReturn("https://example.com/bank/return?state=v1.a.1.b") { submitted += 1 } is ReturnOutcome.Ignored)
    assertEquals(0, submitted)
    assertEquals(binding, attempt.idempotencyKey)
  }

  private fun signer(): ReturnStateSigner = ReturnStateSigner(secret)

  private fun stateToken(handoffUrl: String): String {
    val query = java.net.URI(handoffUrl).rawQuery
    val raw = query.split("&").first { it.startsWith("state=") }.removePrefix("state=")
    return java.net.URLDecoder.decode(raw, "UTF-8")
  }
}
