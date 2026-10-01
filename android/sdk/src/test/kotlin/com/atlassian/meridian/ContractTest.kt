package com.atlassian.meridian

import com.fasterxml.jackson.databind.DeserializationFeature
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import org.junit.Assert.*
import org.junit.Test

/**
 * Consumer-driven contract tests for catalog and payment intent schemas.
 *
 * Verifies:
 * - Backward compatibility for legacy integer-pence payloads
 * - Extended schemas with additional optional fields (forward-compat)
 * - Adyen + Worldpay provider baseline – exactly two providers
 * - Missing optional fields decoded as null rather than throwing
 */
class ContractTest {

  /** Lenient mapper: ignores unknown fields to verify forward-compatibility. */
  private val mapper = ObjectMapper()
    .registerKotlinModule()
    .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false)

  // C1: Legacy Transaction – bare integer amount field
  @Test
  fun `legacy Transaction integer amount field decodes correctly`() {
    val json = """
      {
        "id": "txn-legacy-001",
        "reference": "REF-20260905-001",
        "recipientId": "birch-bloom",
        "name": "Birch & Bloom",
        "category": "Food & drink",
        "amount": 3500,
        "date": "2026-09-05",
        "provider": "worldpay",
        "method": "bank",
        "status": "completed",
        "note": "Legacy payload"
      }
    """.trimIndent()

    val txn = mapper.readValue(json, Transaction::class.java)

    assertEquals(3500, txn.amount)
    assertEquals("worldpay", txn.provider)
    assertEquals("bank", txn.method)
  }

  // C2: CatalogResponse tolerates extra unknown fields (forward-compat)
  @Test
  fun `CatalogResponse ignores extra unknown fields`() {
    val json = """
      {
        "demoDate": "2026-09-18",
        "schemaVersion": "2.0",
        "currencyCode": "GBP",
        "recipients": [
          {
            "id": "birch-bloom",
            "name": "Birch & Bloom",
            "initials": "BB",
            "detail": "Organic café",
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

    val catalog = mapper.readValue(json, CatalogResponse::class.java)

    assertEquals("2026-09-18", catalog.demoDate)
    assertEquals(1, catalog.recipients.size)
    assertEquals(2, catalog.providers.size)
  }

  // C3: Provider baseline – exactly Adyen (card) and Worldpay (bank)
  @Test
  fun `provider baseline is Adyen card and Worldpay bank only`() {
    val json = """
      {
        "demoDate": "2026-09-18",
        "recipients": [],
        "providers": [
          {"id": "adyen",    "name": "Adyen",    "description": "Card processor", "methods": ["card"]},
          {"id": "worldpay", "name": "Worldpay", "description": "Bank processor", "methods": ["bank"]}
        ]
      }
    """.trimIndent()

    val catalog = mapper.readValue(json, CatalogResponse::class.java)

    assertEquals(2, catalog.providers.size)
    val adyen    = catalog.providers.first { it.id == "adyen" }
    val worldpay = catalog.providers.first { it.id == "worldpay" }
    assertNotNull(adyen)
    assertNotNull(worldpay)
    assertTrue(adyen!!.methods.contains("card"))
    assertTrue(worldpay!!.methods.contains("bank"))
  }

  // C4: PaymentResponse – legacy format without paymentId
  @Test
  fun `PaymentResponse legacy format decoded without paymentId`() {
    val json = """
      {
        "ok": true,
        "state": {
          "version": 1,
          "balance": 1244951,
          "transactions": [],
          "budgets": []
        },
        "transaction": {
          "id": "txn-002",
          "reference": "REF-20260919-002",
          "recipientId": "birch-bloom",
          "name": "Birch & Bloom",
          "category": "Food & drink",
          "amount": 3099,
          "date": "2026-09-19",
          "provider": "adyen",
          "method": "card",
          "status": "completed",
          "note": "Coffee"
        }
      }
    """.trimIndent()

    val response = mapper.readValue(json, PaymentResponse::class.java)

    assertTrue(response.ok)
    assertNull(response.paymentId)
    assertEquals(3099, response.transaction?.amount)
  }

  // C5: PaymentResponse – new format with paymentId (pending)
  @Test
  fun `PaymentResponse extended format with paymentId decodes correctly`() {
    val json = """
      {
        "ok": false,
        "error": "Payment pending confirmation",
        "code": "PAYMENT_PENDING",
        "paymentId": "pay-uuid-abc123",
        "state": null,
        "transaction": null
      }
    """.trimIndent()

    val response = mapper.readValue(json, PaymentResponse::class.java)

    assertFalse(response.ok)
    assertEquals("PAYMENT_PENDING", response.code)
    assertEquals("pay-uuid-abc123", response.paymentId)
  }

  // C6: BankState – legacy integer balance field
  @Test
  fun `BankState legacy integer balance field decodes correctly`() {
    val json = """
      {
        "version": 1,
        "balance": 1248050,
        "transactions": [],
        "budgets": []
      }
    """.trimIndent()

    val state = mapper.readValue(json, BankState::class.java)

    assertEquals(1_248_050, state.balance)
    assertEquals(1, state.version)
  }

  // C7: BankState – extended with unknown metadata fields
  @Test
  fun `BankState tolerates unknown metadata fields`() {
    val json = """
      {
        "version": 2,
        "balance": 500000,
        "currency": "GBP",
        "lastSyncedAt": "2026-09-19T12:00:00Z",
        "transactions": [],
        "budgets": []
      }
    """.trimIndent()

    val state = mapper.readValue(json, BankState::class.java)

    assertEquals(500_000, state.balance)
    assertEquals(2, state.version)
  }

  // C8: PaymentRequest round-trips through JSON encode/decode
  @Test
  fun `PaymentRequest JSON encode-decode round-trip`() {
    val request = PaymentRequest(
      recipientId = "northline-studio",
      amountMinor = 2599,
      method = "card",
      note = "Design tools",
      scenario = "success",
    )

    val encoded = mapper.writeValueAsString(request)
    val decoded = mapper.readValue(encoded, PaymentRequest::class.java)

    assertEquals(request.recipientId, decoded.recipientId)
    assertEquals(request.amountMinor, decoded.amountMinor)
    assertEquals(request.method, decoded.method)
  }

  // C9: Missing optional PaymentResponse fields decode to null
  @Test
  fun `missing optional PaymentResponse fields decode to null`() {
    val json = """
      {
        "ok": false,
        "error": "Declined",
        "code": "DECLINED"
      }
    """.trimIndent()

    val response = mapper.readValue(json, PaymentResponse::class.java)

    assertFalse(response.ok)
    assertNull(response.state)
    assertNull(response.transaction)
    assertNull(response.paymentId)
  }

  // C10: CatalogResponse with all five categories
  @Test
  fun `CatalogResponse recipients cover all five category values`() {
    val json = """
      {
        "demoDate": "2026-09-18",
        "recipients": [
          {"id":"r1","name":"Shop","initials":"SH","detail":"d","category":"Shopping","color":"#F00"},
          {"id":"r2","name":"Cafe","initials":"CA","detail":"d","category":"Food & drink","color":"#0F0"},
          {"id":"r3","name":"Bus","initials":"BU","detail":"d","category":"Transport","color":"#00F"},
          {"id":"r4","name":"Bill","initials":"BI","detail":"d","category":"Bills","color":"#FF0"},
          {"id":"r5","name":"Gym","initials":"GY","detail":"d","category":"Lifestyle","color":"#0FF"}
        ],
        "providers": []
      }
    """.trimIndent()

    val catalog = mapper.readValue(json, CatalogResponse::class.java)
    val categories = catalog.recipients.map { it.category }.toSet()

    assertEquals(5, categories.size)
    assertTrue(categories.contains("Shopping"))
    assertTrue(categories.contains("Food & drink"))
    assertTrue(categories.contains("Transport"))
    assertTrue(categories.contains("Bills"))
    assertTrue(categories.contains("Lifestyle"))
  }
}
