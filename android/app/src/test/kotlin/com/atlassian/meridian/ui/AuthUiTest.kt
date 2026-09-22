package com.atlassian.meridian.ui

import kotlin.test.AfterTest
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.Test

/**
 * Unit tests for the Compose-free logic behind the new authentication UI:
 * the feature flag default and the grouped card-field formatting/validation.
 */
class AuthUiTest {

  @AfterTest
  fun clearOverride() {
    FeatureFlags.override(null)
  }

  // MARK: - Feature flag

  @Test
  fun featureFlagIsOffByDefault() {
    assertFalse(FeatureFlags.REVAMPED_AUTH_UI_DEFAULT)
    assertFalse(FeatureFlags.revampedAuthUiEnabled)
  }

  @Test
  fun featureFlagRuntimeOverride() {
    FeatureFlags.override(true)
    assertTrue(FeatureFlags.revampedAuthUiEnabled)
    FeatureFlags.override(false)
    assertFalse(FeatureFlags.revampedAuthUiEnabled)
    FeatureFlags.override(null)
    assertFalse(FeatureFlags.revampedAuthUiEnabled)
  }

  // MARK: - Expiry formatting

  @Test
  fun expiryFormatsAsMonthSlashYear() {
    assertEquals("", CardFieldFormat.formatExpiry(""))
    assertEquals("1", CardFieldFormat.formatExpiry("1"))
    assertEquals("12", CardFieldFormat.formatExpiry("12"))
    assertEquals("12/2", CardFieldFormat.formatExpiry("122"))
    assertEquals("12/25", CardFieldFormat.formatExpiry("1225"))
  }

  @Test
  fun expiryStripsNonDigitsAndCaps() {
    assertEquals("12/25", CardFieldFormat.formatExpiry("12/25"))
    assertEquals("12/25", CardFieldFormat.formatExpiry("1a2b25"))
    assertEquals("12/25", CardFieldFormat.formatExpiry("122599"))
  }

  @Test
  fun expiryValidation() {
    assertTrue(CardFieldFormat.isValidExpiry("01/25"))
    assertTrue(CardFieldFormat.isValidExpiry("12/30"))
    assertFalse(CardFieldFormat.isValidExpiry("00/25"))
    assertFalse(CardFieldFormat.isValidExpiry("13/25"))
    assertFalse(CardFieldFormat.isValidExpiry("1/25"))
    assertFalse(CardFieldFormat.isValidExpiry("12/5"))
    assertFalse(CardFieldFormat.isValidExpiry(""))
  }

  // MARK: - CVV formatting

  @Test
  fun cvvKeepsDigitsAndCaps() {
    assertEquals("123", CardFieldFormat.formatCvv("123"))
    assertEquals("123", CardFieldFormat.formatCvv("1a2b3c"))
    assertEquals("1234", CardFieldFormat.formatCvv("123456"))
  }

  @Test
  fun cvvValidation() {
    assertTrue(CardFieldFormat.isValidCvv("123"))
    assertTrue(CardFieldFormat.isValidCvv("1234"))
    assertFalse(CardFieldFormat.isValidCvv("12"))
    assertFalse(CardFieldFormat.isValidCvv("12345"))
    assertFalse(CardFieldFormat.isValidCvv(""))
  }
}
