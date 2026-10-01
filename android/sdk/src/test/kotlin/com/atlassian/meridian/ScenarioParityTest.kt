package com.atlassian.meridian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ScenarioParityTest {
  private var sequence = 0

  private fun model(): PaymentScreenModel {
    sequence = 0
    return PaymentScreenModel(endpoint = "http://127.0.0.1:8080/api/v1", room = "room-one").also {
      it.keyFactory = {
        sequence += 1
        "key-$sequence"
      }
    }
  }

  @Test
  fun moneyFormatting() {
    assertEquals("£0.01", money(1))
    assertEquals("£1.00", money(100))
    assertEquals("£10.50", money(1050))
    assertEquals("£10,000.00", money(1_000_000))
    assertEquals("£12,480.50", money(1_248_050))
    assertEquals("-£10.50", money(-1050))
  }

  @Test
  fun cacheExpiry() {
    val screen = model()
    val catalog = CachedCatalog("2026-09-18", "GBP", listOf("northline-studio"), listOf("adyen", "worldpay"))
    screen.rememberCatalog(catalog, 1_000)
    assertEquals(catalog, screen.cachedCatalog(1_000, 5_000))
    assertEquals(catalog, screen.cachedCatalog(5_999, 5_000))
    assertNull(screen.cachedCatalog(6_000, 5_000))
    val restored = PaymentScreenModel.restore(screen.checkpointJson())
    assertEquals(catalog, restored?.cachedCatalog(2_000, 5_000))
    assertNull(restored?.cachedCatalog(6_000, 5_000))
  }

  @Test
  fun idempotencyPersistence() {
    val screen = model()
    assertTrue(screen.connect())
    screen.amountInput = "10.50"
    screen.method = PaymentMethod.card
    assertTrue(screen.review())
    val key = screen.submitInstruction()?.idempotencyKey
    screen.markUncertain("network")
    assertTrue(screen.review())
    assertEquals(key, screen.submitInstruction()?.idempotencyKey)
    assertEquals(key, screen.requestHeaders(true)["Idempotency-Key"])
    screen.edit()
    assertEquals(key, screen.submitInstruction()?.idempotencyKey)
    assertTrue(screen.reviewing)
  }

  @Test
  fun processDeath() {
    val screen = model()
    assertTrue(screen.connect())
    screen.amountInput = "25.99"
    screen.note = "Desk lamp"
    screen.method = PaymentMethod.card
    assertTrue(screen.review())
    val draft = screen.submitInstruction()
    val restored = PaymentScreenModel.restore(screen.checkpointJson())
    val again = restored?.submitInstruction()
    assertEquals(draft?.idempotencyKey, again?.idempotencyKey)
    assertEquals(true, again?.outcomeUncertain)
    assertEquals("adyen", again?.provider)
    assertEquals("card", again?.method)
    assertEquals(screen.runtime.checkpoint.sessionId, restored?.room)
    assertEquals(screen.runtime.checkpoint.sessionId, restored?.requestHeaders(true)?.get("X-Rehearsal-Session"))
    assertEquals(true, restored?.reviewing)
  }

  @Test
  fun providerStickyOnTimeout() {
    val screen = model()
    assertTrue(screen.connect())
    screen.amountInput = "10.00"
    screen.method = PaymentMethod.card
    assertTrue(screen.review())
    val key = screen.submitInstruction()?.idempotencyKey
    screen.markUncertain("timeout")
    screen.method = PaymentMethod.bank
    val draft = screen.submitInstruction()
    assertEquals(key, draft?.idempotencyKey)
    assertEquals("adyen", draft?.provider)
    assertEquals("card", draft?.method)
  }

  @Test
  fun sessionPreserved() {
    val screen = model()
    screen.room = "room-two"
    assertTrue(screen.connect())
    assertEquals("room-two", screen.requestHeaders(false)["X-Rehearsal-Session"])
    screen.room = "no"
    assertFalse(screen.connect())
    assertEquals("room-two", screen.requestHeaders(false)["X-Rehearsal-Session"])
    assertEquals("room-two", screen.runtime.checkpoint.sessionId)
  }

  @Test
  fun replayedDeepLink() {
    val screen = model()
    val now = 1_700_000_000_000
    val url = "meridian://return?paymentId=pay-1&nonce=n1&exp=${now + 10_000}"
    val first = screen.openReturn(url, now)
    assertTrue(first is ReturnDecision.Accepted && first.paymentId == "pay-1")
    val second = screen.openReturn(url, now + 1)
    assertTrue(second is ReturnDecision.Rejected && second.reason == "replayed")
    val restored = PaymentScreenModel.restore(screen.checkpointJson())
    val third = restored?.openReturn(url, now + 2)
    assertTrue(third is ReturnDecision.Rejected && third.reason == "replayed")
  }

  @Test
  fun expiredReturnState() {
    val screen = model()
    val now = 1_700_000_000_000
    val expired = screen.openReturn("meridian://return?paymentId=pay-2&nonce=n2&exp=$now", now)
    assertTrue(expired is ReturnDecision.Rejected && expired.reason == "expired")
    val malformed = screen.openReturn("https://example.invalid/return?paymentId=pay-3&nonce=n3&exp=${now + 10}", now)
    assertTrue(malformed is ReturnDecision.Rejected && malformed.reason == "malformed")
    val missing = screen.openReturn("meridian://return?paymentId=pay-4&exp=${now + 10}", now)
    assertTrue(missing is ReturnDecision.Rejected && missing.reason == "malformed")
    assertTrue(screen.runtime.checkpoint.consumedReturnNonces.isEmpty())
  }

  @Test
  fun malformedCatalog() {
    val result = ConsumerContract.evaluateCatalog(File(contractsDirectory(), "catalog-malformed.json").readText())
    assertFalse(result.accepted)
    assertEquals("MALFORMED_CATALOG", result.code)
    assertTrue(result.detail.contains("unknown_provider"))
    assertTrue(result.detail.contains("unknown_category"))
    assertTrue(result.providerIds.isEmpty())
  }

  @Test
  fun voiceOverLabel() {
    val descriptor = paymentConfirmationAccessibility("£10.50", "Northline Studio", "card", "en", 1.0, "voiceover")
    assertEquals("Confirm payment of £10.50 to Northline Studio using debit card, Adyen", descriptor.label)
    assertEquals("Submits the fictional rehearsal payment. No real money moves.", descriptor.hint)
    assertEquals("button", descriptor.role)
    assertTrue(descriptor.minimumTouchTargetPt >= 44)
    assertEquals("ltr", descriptor.layoutDirection)
    assertTrue(descriptor.mirrorsInRightToLeft)
  }

  @Test
  fun talkBackLabel() {
    val voice = paymentConfirmationAccessibility("£10.50", "Northline Studio", "card", "en", 1.0, "voiceover")
    val talk = paymentConfirmationAccessibility("£10.50", "Northline Studio", "bank", "en-GB", 1.0, "talkback")
    assertEquals("Confirm payment of £10.50 to Northline Studio using bank payment, Worldpay", talk.label)
    assertEquals(voice.hint, talk.hint)
    assertTrue(talk.minimumTouchTargetPt >= 48)
    assertEquals("button", talk.role)
  }

  @Test
  fun largeFontScaling() {
    val standard = scaledFontSize(38.0, fontScaleFor("standard"))
    val large = scaledFontSize(38.0, fontScaleFor("large"))
    val accessibility = scaledFontSize(38.0, fontScaleFor("accessibility"))
    assertEquals(1.3, fontScaleFor("large"), 0.0)
    assertTrue(large > standard)
    assertEquals(76.0, accessibility, 0.0)
    assertEquals(49.4, large, 0.0)
  }

  @Test
  fun rtlLayout() {
    assertEquals("ltr", layoutDirectionForLanguage("en"))
    assertEquals("ltr", layoutDirectionForLanguage("en-GB"))
    assertEquals("rtl", layoutDirectionForLanguage("ar"))
    assertEquals("rtl", layoutDirectionForLanguage("he"))
    val descriptor = paymentConfirmationAccessibility("£1.00", "Northline Studio", "card", "ar", fontScaleFor("large"), "voiceover")
    assertEquals("rtl", descriptor.layoutDirection)
  }

  @Test
  fun uncertainStatusCodes() {
    assertTrue(PaymentScreenModel.failureIsUncertain(null))
    assertTrue(PaymentScreenModel.failureIsUncertain(202))
    assertTrue(PaymentScreenModel.failureIsUncertain(503))
    assertFalse(PaymentScreenModel.failureIsUncertain(400))
    assertFalse(PaymentScreenModel.failureIsUncertain(422))
    assertFalse(PaymentScreenModel.failureIsUncertain(409))
  }
}
