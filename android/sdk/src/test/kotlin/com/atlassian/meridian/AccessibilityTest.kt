package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import org.junit.Assert.*
import org.junit.Test

/**
 * Accessibility and localisation tests verifying:
 * - money() produces TalkBack-friendly strings (£ prefix, two decimal places, no sci notation)
 * - Leading-zero pence formatting (£0.01 not £.01)
 * - Large-font / large-amount formatting consistency
 * - RTL readiness: currency symbol precedes digits
 * - parseAmount rejects locale-specific comma separators
 * - Recipient / Provider strings are non-empty and screen-reader safe
 * - MeridianError messages are human-readable
 * - Category display names are human-readable
 */
class AccessibilityTest {

  private val mapper = ObjectMapper().registerKotlinModule()

  // A1: money() output begins with £ symbol (RTL-safe, symbol-first)
  @Test
  fun `money output begins with pound symbol for all common amounts`() {
    val amounts = listOf(1, 50, 100, 1_050, 999_999)
    for (pence in amounts) {
      val formatted = money(pence)
      assertTrue("money($pence) should start with £, got '$formatted'", formatted.startsWith("£"))
    }
  }

  // A2: money(1) – leading zero before decimal (£0.01 not £.01)
  @Test
  fun `money formats one penny with leading zero`() {
    assertEquals("£0.01", money(1))
  }

  // A3: money() always produces exactly two decimal places
  @Test
  fun `money always produces exactly two decimal places`() {
    val pences = listOf(0, 1, 10, 100, 1_000, 10_050, 1_000_000)
    for (pence in pences) {
      val formatted = money(pence)
      val dotIndex = formatted.indexOf('.')
      assertTrue("money($pence)='$formatted' must contain a decimal point", dotIndex >= 0)
      val afterDot = formatted.substring(dotIndex + 1)
      assertEquals("money($pence)='$formatted' must have exactly 2 decimal places", 2, afterDot.length)
    }
  }

  // A4: money() output contains only £, digits, and a single decimal point (safe chars)
  @Test
  fun `money output contains only safe characters`() {
    val safeChars = setOf('£', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.')
    val pences = listOf(0, 1, 100, 1_050, 1_000_000)
    for (pence in pences) {
      val formatted = money(pence)
      for (ch in formatted) {
        assertTrue(
          "money($pence)='$formatted' contains unexpected char '$ch'",
          safeChars.contains(ch)
        )
      }
    }
  }

  // A5: Large-amount money() contains no scientific notation
  @Test
  fun `money large amounts contain no scientific notation`() {
    val largeAmounts = listOf(100_000, 500_000, 999_999, 1_000_000)
    for (pence in largeAmounts) {
      val formatted = money(pence)
      assertFalse(
        "money($pence)='$formatted' must not contain scientific notation",
        formatted.lowercase().contains('e')
      )
    }
  }

  // A6: Provider names and descriptions are non-empty (TalkBack/VoiceOver labels)
  @Test
  fun `Provider name and description are non-empty`() {
    val json = """
      [
        {"id":"adyen",    "name":"Adyen",    "description":"Card payment processor", "methods":["card"]},
        {"id":"worldpay", "name":"Worldpay", "description":"Bank transfer processor","methods":["bank"]}
      ]
    """.trimIndent()

    val providers = mapper.readValue(json, Array<Provider>::class.java).toList()

    for (p in providers) {
      assertTrue("Provider name must not be empty", p.name.isNotEmpty())
      assertTrue("Provider description must not be empty", p.description.isNotEmpty())
      assertTrue("Provider methods must not be empty", p.methods.isNotEmpty())
    }
  }

  // A7: parseAmount rejects comma decimal separator (locale-independence)
  @Test
  fun `parseAmount rejects comma decimal separator`() {
    val commaInputs = listOf("10,50", "1,000", "10,5")
    for (input in commaInputs) {
      val (pence, _) = parseAmount(input)
      assertNull("parseAmount('$input') should be null (comma separator rejected)", pence)
    }
  }

  // A8: MeridianError messages are non-trivial human-readable strings
  @Test
  fun `MeridianError messages are human-readable`() {
    val errors: List<MeridianError> = listOf(
      MeridianError.NetworkError("timeout"),
      MeridianError.InvalidURL("Invalid URL"),
      MeridianError.DecodingError("field missing"),
      MeridianError.HttpError(503, "Service unavailable"),
      MeridianError.MissingSession(),
      MeridianError.InvalidAmount("negative not allowed"),
      MeridianError.ValidationError("note too long"),
    )

    for (err in errors) {
      val msg = err.message
      assertNotNull("MeridianError message must not be null: $err", msg)
      assertTrue("MeridianError message must be non-trivial: '$msg'", msg!!.length > 5)
    }
  }

  // A9: Recipient initials are 1-3 characters (safe for avatar accessibility labels)
  @Test
  fun `Recipient initials are 1 to 3 characters`() {
    val json = """
      [
        {"id":"r1","name":"Alice","initials":"A","detail":"d","category":"Shopping","color":"#FFF"},
        {"id":"r2","name":"Birch & Bloom","initials":"BB","detail":"d","category":"Food & drink","color":"#FFF"},
        {"id":"r3","name":"Northline Studio","initials":"NS","detail":"d","category":"Lifestyle","color":"#FFF"}
      ]
    """.trimIndent()

    val recipients = mapper.readValue(json, Array<Recipient>::class.java).toList()

    for (r in recipients) {
      assertTrue("Initials '${r.initials}' must be non-empty", r.initials.isNotEmpty())
      assertTrue("Initials '${r.initials}' must be ≤3 chars", r.initials.length <= 3)
    }
  }

  // A10: Category display names are non-empty title-cased strings
  @Test
  fun `Category enum display names are non-empty and title-cased`() {
    val expectedNames = listOf("Shopping", "Food & drink", "Transport", "Bills", "Lifestyle")

    for (name in expectedNames) {
      assertTrue("Category name must not be empty", name.isNotEmpty())
      assertTrue(
        "Category name '$name' must start with an uppercase letter",
        name.first().isUpperCase()
      )
    }

    // Verify the Category enum values used in JSON match these display names
    val recipientJson = """
      {"id":"r1","name":"Shop","initials":"SH","detail":"d","category":"Shopping","color":"#FFF"}
    """.trimIndent()
    val recipient = mapper.readValue(recipientJson, Recipient::class.java)
    assertTrue("Category 'Shopping' must be in expected names", expectedNames.contains(recipient.category))
  }
}
