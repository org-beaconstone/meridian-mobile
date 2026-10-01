package com.atlassian.meridian

import com.fasterxml.jackson.databind.DeserializationFeature
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import org.junit.Assert.*
import org.junit.Test

/**
 * Consumer-driven contract tests for catalog and payment intent schemas.
 *
 * Validates backward compatibility with legacy integer (pence) payloads and
 * forward compatibility when unknown optional fields (e.g. a future `currency`
 * hint) appear in API responses.
 */
class ContractTest {
  private val mapper = ObjectMapper()
    .registerKotlinModule()
    .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false)

  // -------------------------------------------------------------------------
  // Catalog schema contracts
  // -------------------------------------------------------------------------

  @Test
  fun contractCatalogResponseRequiredFields() {
    val json = """
      {
        "demoDate": "2026-09-18",
        "recipients": [
          {
            "id": "birch-bloom",
            "name": "Birch & Bloom",
            "initials": "BB",
            "detail": "Organic café & bistro",
            "category": "Food & drink",
            "color": "#FFD93D"
          }
        ],
        "providers": [
          {
            "id": "adyen",
            "name": "Adyen",
            "description": "Card payment processor",
            "methods": ["card"]
          },
          {
            "id": "worldpay",
            "name": "Worldpay",
            "description": "Bank transfer processor",
            "methods": ["bank"]
          }
        ]
      }
    """.trimIndent()
    val response = mapper.readValue(json, CatalogResponse::class.java)
    assertEquals("2026-09-18", response.demoDate)
    assertEquals(1, response.recipients.size)
    assertEquals("birch-bloom", response.recipients[0].id)
    assertEquals("BB", response.recipients[0].initials)
    assertEquals(2, response.providers.size)
    assertTrue(response.providers.any { it.id == "adyen" })
    assertTrue(response.providers.any { it.id == "worldpay" })
  }

  @Test
  fun contractCatalogLegacyIntegerAmountInPence() {
    // Transaction.amount is an integer (pence) - backward compat must be preserved
    val json = """
      {
        "version": 1,
        "balance": 500000,
        "transactions": [
          {
            "id": "txn-legacy",
            "reference": "REF-001",
            "recipientId": "rec-001",
            "name": "Legacy Merchant",
            "category": "Shopping",
            "amount": 1050,
            "date": "2026-01-01",
            "provider": "adyen",
            "method": "card",
            "status": "completed",
            "note": "legacy payment"
          }
        ],
        "budgets": []
      }
    """.trimIndent()
    val state = mapper.readValue(json, BankState::class.java)
    assertEquals(1050, state.transactions[0].amount)
    // Integer pence 1050 must format as £10.50
    assertEquals("£10.50", money(state.transactions[0].amount))
  }

  @Test
  fun contractCatalogIgnoresUnknownCurrencyField() {
    // Forward compat: a future `currency` field must not break decoding
    val json = """
      {
        "demoDate": "2026-09-18",
        "currency": "GBP",
        "recipients": [],
        "providers": []
      }
    """.trimIndent()
    val response = mapper.readValue(json, CatalogResponse::class.java)
    assertEquals("2026-09-18", response.demoDate)
    assertTrue(response.recipients.isEmpty())
  }

  @Test
  fun contractCatalogOnlyAdyenAndWorldpayProviders() {
    // Contract: only adyen and worldpay are valid provider IDs in this baseline
    val validProviders = setOf("adyen", "worldpay")
    val json = """
      {
        "demoDate": "2026-09-18",
        "recipients": [],
        "providers": [
          {"id": "adyen",    "name": "Adyen",    "description": "Card", "methods": ["card"]},
          {"id": "worldpay", "name": "Worldpay", "description": "Bank", "methods": ["bank"]}
        ]
      }
    """.trimIndent()
    val response = mapper.readValue(json, CatalogResponse::class.java)
    response.providers.forEach { provider ->
      assertTrue("Unknown provider: ${provider.id}", provider.id in validProviders)
    }
  }

  @Test
  fun contractAllCategoryValues() {
    // Contract: all five canonical category strings must deserialise
    val categories = listOf("Shopping", "Food & drink", "Transport", "Bills", "Lifestyle")
    categories.forEach { cat ->
      val json = """
        {
          "id": "rec-$cat", "name": "Test", "initials": "T",
          "detail": "Detail", "category": "$cat", "color": "#000"
        }
      """.trimIndent()
      val recipient = mapper.readValue(json, Recipient::class.java)
      assertEquals(cat, recipient.category)
    }
  }

  // -------------------------------------------------------------------------
  // Payment intent schema contracts
  // -------------------------------------------------------------------------

  @Test
  fun contractPaymentRequestLegacyIntegerAmountMinor() {
    // amountMinor is always an integer (pence); no decimal or string forms
    val request = PaymentRequest(
      recipientId = "birch-bloom",
      amountMinor = 500,   // £5.00
      method = "card",
      note = "Coffee",
      scenario = "success"
    )
    val json = mapper.writeValueAsString(request)
    val parsed = mapper.readValue(json, PaymentRequest::class.java)
    assertEquals(500, parsed.amountMinor)
    assertEquals("birch-bloom", parsed.recipientId)
    assertEquals("card", parsed.method)
  }

  @Test
  fun contractPaymentResponseOkFieldIsMandatory() {
    val successJson = """{"ok": true, "state": null, "transaction": null}"""
    val failJson    = """{"ok": false, "error": "Declined", "code": "DECLINED"}"""
    val success = mapper.readValue(successJson, PaymentResponse::class.java)
    val fail    = mapper.readValue(failJson, PaymentResponse::class.java)
    assertTrue(success.ok)
    assertFalse(fail.ok)
  }

  @Test
  fun contractPaymentResponsePaymentIdPresentForPending() {
    // When code == PAYMENT_PENDING the paymentId field must be present
    val json = """
      {
        "ok": false,
        "code": "PAYMENT_PENDING",
        "paymentId": "pay-abc-123",
        "error": "Awaiting confirmation"
      }
    """.trimIndent()
    val response = mapper.readValue(json, PaymentResponse::class.java)
    assertFalse(response.ok)
    assertEquals("PAYMENT_PENDING", response.code)
    assertNotNull("paymentId must be present for PAYMENT_PENDING", response.paymentId)
    assertEquals("pay-abc-123", response.paymentId)
  }

  @Test
  fun contractPaymentResponseIgnoresUnknownCurrencyFields() {
    // Forward compat: unknown currency-related fields must be silently ignored
    val json = """
      {
        "ok": true,
        "currency": "GBP",
        "currencyMinorUnits": 2,
        "state": {"version": 1, "balance": 100000, "transactions": [], "budgets": []},
        "transaction": null
      }
    """.trimIndent()
    val response = mapper.readValue(json, PaymentResponse::class.java)
    assertTrue(response.ok)
    assertNotNull(response.state)
    assertEquals(100_000, response.state?.balance)
  }

  @Test
  fun contractBankStateVersionIsNonNegativeInteger() {
    val json = """{"version": 42, "balance": 0, "transactions": [], "budgets": []}"""
    val state = mapper.readValue(json, BankState::class.java)
    assertEquals(42, state.version)
    assertTrue(state.version >= 0)
  }

  @Test
  fun contractAllTransactionStatusValues() {
    // Contract: status must be one of completed | declined | pending
    listOf("completed", "declined", "pending").forEach { status ->
      val json = """
        {
          "id": "txn-$status", "reference": "REF-$status",
          "recipientId": "rec-1", "name": "Test", "category": "Shopping",
          "amount": 100, "date": "2026-01-01",
          "provider": "adyen", "method": "card",
          "status": "$status", "note": ""
        }
      """.trimIndent()
      val txn = mapper.readValue(json, Transaction::class.java)
      assertEquals(status, txn.status)
    }
  }

  @Test
  fun contractPaymentMethodValues() {
    // Contract: method must be card or bank; no third value
    listOf("card", "bank").forEach { method ->
      val request = PaymentRequest("rec-1", 1000, method, "", "success")
      val json = mapper.writeValueAsString(request)
      assertTrue("Serialised method must match", json.contains("\"method\":\"$method\""))
    }
  }

  @Test
  fun contractBudgetLimitIsIntegerPence() {
    val json = """{"category": "Shopping", "limit": 100000}"""
    val budget = mapper.readValue(json, Budget::class.java)
    assertEquals("Shopping", budget.category)
    assertEquals(100_000, budget.limit)
    assertEquals("£1000.00", money(budget.limit))
  }
}
