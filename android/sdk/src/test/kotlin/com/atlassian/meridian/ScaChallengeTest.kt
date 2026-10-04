package com.atlassian.meridian

import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetSocketAddress

class ScaChallengeTest {
  private val now = 1_700_000_000L

  private fun binding(amount: Int = 2599, key: String = "pay-key-1") = ScaPaymentBinding(
    recipientId = "northline-studio",
    amountMinor = amount,
    method = PaymentMethod.card,
    idempotencyKey = key,
  )

  private fun engine(binding: ScaPaymentBinding = binding()): ScaChallengeEngine =
    ScaChallengeEngine(binding, challengeId = "challenge-1", nonceProvider = { "nonce-1" })

  private fun enter(engine: ScaChallengeEngine, pin: String, at: Long = now): ScaSnapshot {
    var snap = engine.snapshot(at)
    for (digit in pin) {
      snap = engine.appendDigit(digit.digitToInt(), at)
    }
    return snap
  }

  @Test
  fun hmacMatchesKnownVector() {
    val mac = hmacSha256(
      "key".toByteArray(Charsets.UTF_8),
      "The quick brown fox jumps over the lazy dog".toByteArray(Charsets.UTF_8),
    )
    assertEquals(
      "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8",
      mac.joinToString("") { "%02x".format(it) },
    )
  }

  @Test
  fun base64UrlRoundTrip() {
    for (size in 0..8) {
      val data = ByteArray(size) { (it * 17).toByte() }
      assertArrayEquals(data, decodeBase64Url(base64Url(data)))
    }
  }

  @Test
  fun biometricRejectionShowsPasscodeBanner() {
    val engine = engine()
    val snap = engine.rejectBiometrics(now)
    assertEquals(ScaPhase.Passcode, snap.phase)
    assertEquals(ScaChallenge.REJECTION_BANNER, snap.rejectionBanner)
    assertEquals(BiometricOutcome.rejected, snap.biometric)
    assertNull(snap.verification)
  }

  @Test
  fun bypassAndUnavailableOmitRejectionBanner() {
    val bypassed = engine().bypassBiometrics(now)
    assertEquals(ScaPhase.Passcode, bypassed.phase)
    assertNull(bypassed.rejectionBanner)
    assertEquals(BiometricOutcome.bypassed, bypassed.biometric)

    val unavailable = engine().markBiometricsUnavailable(now)
    assertEquals(ScaPhase.Passcode, unavailable.phase)
    assertNull(unavailable.rejectionBanner)
    assertEquals(BiometricOutcome.unavailable, unavailable.biometric)
  }

  @Test
  fun biometricSuccessSignsInherenceAndPossession() {
    val engine = engine()
    val snap = engine.succeedBiometrics(now)
    val verification = snap.verification
    assertNotNull(verification)
    assertEquals(listOf(ScaFactor.inherence, ScaFactor.possession), verification!!.factors)
    assertEquals(BiometricOutcome.succeeded, verification.biometric)
    assertTrue(ScaSigner.rehearsal().verify(verification.scaChallengeToken, engine.binding))
    assertFalse(verification.scaChallengeToken.contains(ScaChallenge.REHEARSAL_PIN))
    val payload = ScaSigner.rehearsal().authenticatedPayload(verification.scaChallengeToken)
    assertTrue(payload!!.contains("inherence+possession"))
    assertTrue(payload.contains("meridian-in-app"))
  }

  @Test
  fun passcodeMasksDigitsAndRateLimits() {
    val masking = engine()
    masking.rejectBiometrics(now)
    assertEquals("•○○○○○", masking.appendDigit(1, now).maskedPasscode)
    assertEquals("••○○○○", masking.appendDigit(2, now).maskedPasscode)
    assertFalse(masking.maskedPasscode().any { it.isDigit() })
    assertEquals(2, masking.enteredCount)
    masking.appendDigit(77, now)
    assertEquals(2, masking.enteredCount)
    assertEquals("•○○○○○", masking.deleteDigit(now).maskedPasscode)

    val engine = engine()
    engine.rejectBiometrics(now)
    repeat(4) {
      val snap = enter(engine, "000000")
      assertNull(snap.verification)
      assertEquals(ScaChallenge.INCORRECT_PASSCODE, snap.passcodeMessage)
      assertEquals(0, snap.secondsLocked)
    }
    val locked = enter(engine, "000000")
    assertEquals(ScaChallenge.TOO_MANY_ATTEMPTS, locked.passcodeMessage)
    assertEquals(ScaChallenge.LOCKOUT_SECONDS, locked.secondsLocked)
    assertNull(enter(engine, ScaChallenge.REHEARSAL_PIN, now + 29).verification)
    assertEquals(ScaChallenge.LOCKOUT_SECONDS, engine.secondsLocked(now))

    val verified = enter(engine, ScaChallenge.REHEARSAL_PIN, now + ScaChallenge.LOCKOUT_SECONDS)
    assertNotNull(verified.verification)
    assertEquals(listOf(ScaFactor.knowledge, ScaFactor.possession), verified.verification!!.factors)
    assertEquals(BiometricOutcome.rejected, verified.verification!!.biometric)
    val token = verified.verification!!.scaChallengeToken
    assertFalse(token.contains(ScaChallenge.REHEARSAL_PIN))
    assertFalse(engine.toString().contains(ScaChallenge.REHEARSAL_PIN))
    val payload = ScaSigner.rehearsal().authenticatedPayload(token)!!
    assertTrue(payload.contains("knowledge+possession"))
    assertFalse(payload.contains(ScaChallenge.REHEARSAL_PIN))
    assertTrue(ScaSigner.rehearsal().verify(token, engine.binding))
    assertFalse(ScaSigner.rehearsal().verify(token, binding(amount = 2600)))
    val separator = token.indexOf('.')
    val tampered = token.substring(0, separator + 1) +
      (if (token[separator + 1] == 'A') 'B' else 'A') +
      token.substring(separator + 2)
    assertFalse(ScaSigner.rehearsal().verify(tampered, engine.binding))
  }

  @Test
  fun authorizedPaymentRejectsInvalidTokenBeforeNetwork() {
    val client = MeridianClient("http://127.0.0.1:9/api/v1", "test-session")
    val bad = ScaVerification("not-a-token", listOf(ScaFactor.knowledge, ScaFactor.possession), BiometricOutcome.rejected)
    try {
      runBlocking { client.submitAuthorizedPayment(bad, binding()) }
      throw AssertionError("Expected validation error")
    } catch (error: MeridianError.ValidationError) {
      assertTrue(error.message!!.contains("SCA"))
    }
  }

  @Test
  fun authorizedPaymentOmitsTokenFromApiBody() {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    var body = ""
    var idempotency = ""
    var session = ""
    server.createContext("/api/v1/payments") { exchange ->
      body = exchange.requestBody.readBytes().toString(Charsets.UTF_8)
      idempotency = exchange.requestHeaders.getFirst("Idempotency-Key") ?: ""
      session = exchange.requestHeaders.getFirst("X-Rehearsal-Session") ?: ""
      val response = """{"ok":true,"paymentId":"tx-1"}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, response.length.toLong())
      exchange.responseBody.write(response.toByteArray())
      exchange.close()
    }
    server.start()
    try {
      val payment = binding()
      val engine = engine(payment)
      engine.bypassBiometrics(now)
      val verification = enter(engine, ScaChallenge.REHEARSAL_PIN).verification
      assertNotNull(verification)
      val client = MeridianClient("http://127.0.0.1:${server.address.port}/api/v1", "room-77")
      val response = runBlocking {
        client.submitAuthorizedPayment(verification!!, payment, note = "Coffee")
      }
      assertTrue(response.ok)
      assertEquals("pay-key-1", idempotency)
      assertEquals("room-77", session)
      assertTrue(body.contains("\"recipientId\":\"northline-studio\""))
      assertTrue(body.contains("\"amountMinor\":2599"))
      assertTrue(body.contains("\"method\":\"card\""))
      assertFalse(body.contains("scaChallengeToken"))
      assertFalse(body.contains(ScaChallenge.REHEARSAL_PIN))
      assertFalse(body.contains("nonce-1"))
    } finally {
      server.stop(0)
    }
  }
}
