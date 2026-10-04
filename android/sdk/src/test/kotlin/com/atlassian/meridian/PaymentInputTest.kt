package com.atlassian.meridian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PaymentInputTest {
  @Test
  fun testAmountBoundsAndSpokenLabel() {
    val lower = evaluateAmount("0.01")
    assertTrue(lower.isValid)
    assertEquals(1, lower.minorUnits)
    assertEquals("£", lower.prefix)
    assertEquals("0 pounds and 1 penny", lower.spoken)

    val typical = evaluateAmount("£10.50")
    assertEquals(1050, typical.minorUnits)
    assertEquals("10 pounds and 50 pence", typical.spoken)

    val onePound = evaluateAmount("1")
    assertEquals("1 pound and 0 pence", onePound.spoken)
    assertEquals("1 pound and 1 penny", amountSpokenLabel(101))

    val grouped = evaluateAmount("1,000.50")
    assertEquals(100_050, grouped.minorUnits)

    assertEquals("Amount must be at least £0.01", evaluateAmount("0.00").helper)
    assertEquals("Amount cannot exceed £10,000.00", evaluateAmount("10000.01").helper)
    assertEquals("Use a decimal point for pence, for example 10.50", evaluateAmount("10,50").helper)
    assertFalse(evaluateAmount("").isValid)
    assertEquals("No amount entered", evaluateAmount("").spoken)
    assertTrue(evaluateAmount("10000").isValid)
    assertEquals(1_000_000, evaluateAmount("10000.00").minorUnits)
  }

  @Test
  fun testIbanMod97AndFormatErrors() {
    val spaced = validateIban("gb82 west 1234 5698 7654 32")
    assertTrue(spaced.isValid)
    assertEquals("GB82WEST12345698765432", spaced.normalized)
    assertEquals("IBAN checksum is valid", spaced.helper)

    assertTrue(validateIban("DE89-3704-0044-0532-0130-00").isValid)
    assertTrue(validateIban("FR14 2004 1010 0505 0001 3M02 606").isValid)
    assertTrue(validateIban("NL91ABNA0417164300").isValid)
    assertTrue(validateIban("NO9386011117947").isValid)
    assertEquals("DE89 3704 0044 0532 0130 00", formatIbanGroups("DE89370400440532013000"))

    val checksum = validateIban("GB82WEST12345698765433")
    assertFalse(checksum.isValid)
    assertEquals("IBAN checksum is invalid. Check the account number and try again", checksum.helper)

    assertEquals(
      "IBANs for Germany are 22 characters. Enter 14 more characters",
      validateIban("DE89 3704").helper,
    )
    assertEquals(
      "IBANs for Germany are 22 characters",
      validateIban("DE893704004405320130000").helper,
    )
    assertEquals("Enter the recipient IBAN", validateIban("  ").helper)
    assertEquals(
      "IBAN can contain only letters and numbers",
      validateIban("DE89 3704 0044 0532 0130 0!").helper,
    )
    assertEquals(
      "Enter a European IBAN. US is not a supported country code",
      validateIban("US64SVBKUS6S3300958879").helper,
    )
    assertEquals(
      "The two characters after the country code must be digits",
      validateIban("DEAB370400440532013000").helper,
    )
    assertEquals(
      "IBAN must start with a two-letter country code",
      validateIban("1").helper,
    )
  }

  @Test
  fun testDraftSurvivesTransitionsAndFailures() {
    val draft = PaymentEntry(
      amount = "10.50",
      iban = "DE89370400440532013000",
      reference = "Rent",
      recipientId = "northline-studio",
      method = "bank",
      idempotencyKey = "key-1",
      reviewing = false,
    )
    assertNull(paymentReviewError(draft))
    assertEquals("Enter the recipient IBAN", paymentReviewError(draft.copy(iban = "")))
    assertNull(paymentReviewError(draft.copy(method = "card", iban = "")))
    assertEquals(
      "Enter an amount from £0.01 to £10,000.00",
      paymentReviewError(draft.copy(amount = "")),
    )

    val reviewing = reducePaymentEntry(draft, PaymentEntryEvent.Review("key-2"))
    assertEquals("10.50", reviewing.amount)
    assertEquals("DE89370400440532013000", reviewing.iban)
    assertEquals("Rent", reviewing.reference)
    assertTrue(reviewing.reviewing)
    assertEquals("key-2", reviewing.idempotencyKey)

    val editing = reducePaymentEntry(reviewing, PaymentEntryEvent.Edit("key-3"))
    assertEquals("10.50", editing.amount)
    assertEquals("DE89370400440532013000", editing.iban)
    assertFalse(editing.reviewing)

    val failed = reducePaymentEntry(reviewing, PaymentEntryEvent.NetworkFailure)
    assertEquals(reviewing, failed)
    assertEquals(reviewing, reducePaymentEntry(reviewing, PaymentEntryEvent.Pending))
    assertEquals(reviewing, reducePaymentEntry(reviewing, PaymentEntryEvent.Rejected))

    val switched = reducePaymentEntry(reviewing, PaymentEntryEvent.SessionChanged("key-4"))
    assertEquals("10.50", switched.amount)
    assertEquals("DE89370400440532013000", switched.iban)
    assertFalse(switched.reviewing)
    assertEquals("key-4", switched.idempotencyKey)

    val done = reducePaymentEntry(reviewing, PaymentEntryEvent.Completed("key-5"))
    assertEquals("", done.amount)
    assertEquals("", done.iban)
    assertEquals("", done.reference)
    assertEquals("northline-studio", done.recipientId)
    assertEquals("bank", done.method)
    assertEquals("key-5", done.idempotencyKey)
    assertFalse(done.reviewing)
  }
}
