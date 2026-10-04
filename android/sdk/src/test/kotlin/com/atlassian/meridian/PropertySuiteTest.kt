package com.atlassian.meridian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class PropertySuiteTest {
  @Test
  fun explicitCurrencyBoundaries() {
    assertEquals(1, parseAmount("0.01").first)
    assertEquals(1, roundMajorToMinor("0.01").first)
    assertEquals(1_000_000, parseAmount("10000").first)
    assertEquals(1_000_000, parseAmount("10000.00").first)
    assertEquals(1_000_000, roundMajorToMinor("10000.00").first)
    assertEquals(1_000_000, roundMajorToMinor("10000.004").first)
    assertNull(roundMajorToMinor("10000.005").first)
    assertNull(parseAmount("10000.01").first)
    assertNull(roundMajorToMinor("0.004").first)
    assertEquals(1, roundMajorToMinor("0.005").first)
    assertEquals(200, roundMajorToMinor("1.999").first)
    assertEquals(199, roundMajorToMinor("1.994").first)
    assertNull(parseAmount("10.505").first)
    assertEquals(1051, roundMajorToMinor("10.505").first)
    assertEquals(1050, roundMajorToMinor("10.5").first)
    assertEquals(parseAmount("10.50").first, roundMajorToMinor("10.50").first)
    assertEquals("0.01", formatMinorUnits(gbpMinMinor))
    assertEquals("10000.00", formatMinorUnits(gbpMaxMinor))
  }

  @Test
  fun currencyRoundTripAndHalfUpRounding() {
    forAll("minor units round trip") { rng ->
      val minor = rng.nextInt(gbpMinMinor, gbpMaxMinor + 1)
      val text = formatMinorUnits(minor)
      assertEquals(minor, parseAmount(text).first)
      assertEquals(minor, roundMajorToMinor(text).first)
      assertTrue(minor in gbpMinMinor..gbpMaxMinor)
      val down = rng.nextInt(0, 5)
      assertEquals(minor, roundMajorToMinor(text + down + extraDigits(rng)).first)
      if (minor < gbpMaxMinor) {
        val up = rng.nextInt(5, 10)
        assertEquals(minor + 1, roundMajorToMinor(text + up + extraDigits(rng)).first)
      } else {
        assertNull(roundMajorToMinor(text + "5").first)
      }
    }
  }

  @Test
  fun strictParserAgreesWithRoundingInsideTwoDecimals() {
    val samples = listOf("0.01", "0.10", "1", "10.", "10.5", "10.50", "0004.20", "10000", "10000.00")
    for (sample in samples) {
      assertEquals(sample, parseAmount(sample).first, roundMajorToMinor(sample).first)
    }
    forAll("rejected amounts stay rejected") { rng ->
      val invalid = listOf("", " ", "0", "0.00", "-1", "+1", "1e2", "10000.01", "10001", "£1", "1,000")
      val sample = invalid[rng.nextInt(invalid.size)]
      assertNull(parseAmount(sample).first)
      assertNull(roundMajorToMinor(sample).first)
    }
  }

  @Test
  fun mod97IbanChecksums() {
    val known = listOf(
      "GB82WEST12345698765432",
      "DE89370400440532013000",
      "FR1420041010050500013M02606",
      "GR1601101250000000012300695",
      "GB94BARC10201530093459",
      "NL91ABNA0417164300",
    )
    for (iban in known) {
      assertEquals(1, ibanMod97(iban))
      assertTrue(ibanIsValid(iban))
      assertTrue(ibanIsValid(iban.lowercase().chunked(4).joinToString(" ")))
      assertFalse(ibanIsValid(iban.take(2) + "00" + iban.drop(4)))
    }
    assertEquals("GB82WEST12345698765432", ibanCompose("gb", "WEST12345698765432"))
    assertFalse(ibanIsValid(""))
    assertFalse(ibanIsValid("GB00"))
    assertFalse(ibanIsValid("1234WEST12345698765432"))

    forAll("composed iban validates and a shifted check digit does not") { rng ->
      val country = "" + letter(rng) + letter(rng)
      val length = rng.nextInt(11, 31)
      val bban = buildString(length) { repeat(length) { append(bbanChar(rng)) } }
      val iban = ibanCompose(country, bban)
      assertTrue(ibanIsValid(iban))
      assertEquals(1, ibanMod97(ibanNormalize(iban.chunked(4).joinToString(" ").lowercase())))
      val check = iban.substring(2, 4).toInt()
      val corrupted = iban.take(2) + "%02d".format((check + 1) % 100) + iban.drop(4)
      assertFalse(ibanIsValid(corrupted))
    }
  }

  @Test
  fun simulatedScaFlowsKeepProviderAndKey() {
    assertSimulatedScaFlows()
    forAll("sca properties") { rng ->
      val method = if (rng.nextBoolean()) PaymentMethod.card else PaymentMethod.bank
      val provider = providerFor(method)
      val id = "sca-" + rng.nextInt(1_000_000)
      val key = "key-" + rng.nextInt(1_000_000)

      val passed = ScaChallenge(id, key, method)
      passed.submitBiometric(true)
      assertEquals(ScaStatus.Passed(ScaMethod.biometric), passed.status)
      assertEquals(provider, passed.provider)
      assertEquals(key, passed.paymentKey)

      val fallback = ScaChallenge(id + "-fb", key, method)
      fallback.submitBiometric(false)
      assertTrue(fallback.status is ScaStatus.PasscodeFallback)
      fallback.submitPasscode(fallback.rehearsalPasscode())
      assertEquals(ScaStatus.Passed(ScaMethod.passcode), fallback.status)
      assertEquals(provider, fallback.provider)

      val timed = ScaChallenge(id + "-to", key, method, timeoutSteps = 1)
      timed.advance()
      timed.submitBiometric(true)
      timed.submitPasscode(timed.rehearsalPasscode())
      assertTrue(timed.status is ScaStatus.TimedOut)
      assertEquals(provider, timed.provider)
      assertEquals(key, timed.paymentKey)
      assertEquals(provider, providerFor(method))
    }
  }

  @Test
  fun providerSwitchIsRefused() {
    try {
      refuseProviderSwitch(ProviderId.adyen, ProviderId.worldpay)
      throw AssertionError("Card timeout must not move to Worldpay")
    } catch (e: MeridianError.ValidationError) {
      assertTrue(e.message!!.contains("Refusing to switch provider"))
    }
    assertEquals(ProviderId.adyen, providerFor(PaymentMethod.card))
    assertEquals(ProviderId.worldpay, providerFor(PaymentMethod.bank))
  }

  private fun extraDigits(rng: Random): String = buildString(2) {
    repeat(2) { append(('0'.code + rng.nextInt(10)).toChar()) }
  }

  private fun letter(rng: Random): Char = ('A'.code + rng.nextInt(26)).toChar()

  private fun bbanChar(rng: Random): Char =
    if (rng.nextBoolean()) letter(rng) else ('0'.code + rng.nextInt(10)).toChar()

  private fun forAll(name: String, cases: Int = 200, property: (Random) -> Unit) {
    val rng = Random(20261004)
    repeat(cases) { index ->
      try {
        property(rng)
      } catch (error: AssertionError) {
        throw AssertionError("$name failed on case $index with seed 20261004", error)
      }
    }
  }
}
