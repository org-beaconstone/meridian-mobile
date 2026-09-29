package com.atlassian.meridian

import com.fasterxml.jackson.databind.JsonMappingException
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class MultiCurrencyTest {
  private val mapper = paymentCacheMapper()

  @Test
  fun currencyCodesUseWireValues() {
    assertEquals("GBP", CurrencyCode.gbp.wire)
    assertEquals("EUR", CurrencyCode.eur.wire)
    assertEquals(CurrencyCode.gbp, CurrencyCode.fromWire("GBP"))
    assertEquals(CurrencyCode.eur, CurrencyCode.fromWire("EUR"))
    assertThrows(IllegalArgumentException::class.java) { CurrencyCode.fromWire("gbp") }
  }

  @Test
  fun monetaryAmountSerializesAsIntegerMinorUnits() {
    val tenThousand = MonetaryAmount(1_000_000, CurrencyCode.eur)
    val json = mapper.writeValueAsString(tenThousand)
    assertFalse(json.contains("."))
    assertTrue(json.contains("1000000"))
    assertTrue(json.contains("EUR"))
    val decoded = mapper.readValue(json, MonetaryAmount::class.java)
    assertEquals(1_000_000, decoded.minorUnits)
    assertEquals(CurrencyCode.eur, decoded.currency)

    val zero = mapper.readValue("""{"minorUnits":0,"currency":"GBP"}""", MonetaryAmount::class.java)
    assertEquals(0, zero.minorUnits)
    val cent = mapper.readValue("""{"minorUnits":1,"currency":"EUR"}""", MonetaryAmount::class.java)
    assertEquals(1, cent.minorUnits)
  }

  @Test
  fun boundaryFormattingUsesIntegerArithmetic() {
    assertEquals("£0.00", formatMonetaryAmount(MonetaryAmount(0, CurrencyCode.gbp)))
    assertEquals("€0.00", formatMonetaryAmount(MonetaryAmount(0, CurrencyCode.eur)))
    assertEquals("£0.01", formatMonetaryAmount(MonetaryAmount(1, CurrencyCode.gbp)))
    assertEquals("€0.01", formatMonetaryAmount(MonetaryAmount(1, CurrencyCode.eur)))
    assertEquals("€10,000.00", MonetaryAmount(1_000_000, CurrencyCode.eur).formatted())
    assertEquals("£10,000.00", formatMonetaryAmount(MonetaryAmount(1_000_000, CurrencyCode.gbp)))
  }

  @Test
  fun dynamicProviderBaselineStaysAdyenAndWorldpay() {
    assertEquals(listOf(ProviderId.adyen, ProviderId.worldpay), DynamicProvider.baseline.map { it.id })
    assertTrue(DynamicProvider.baseline.all { it.currencies == listOf(CurrencyCode.gbp) })
    val unknown = """{"id":"unlisted","name":"Unlisted","methods":["card"],"currencies":["EUR"]}"""
    assertThrows(JsonMappingException::class.java) {
      mapper.readValue(unknown, DynamicProvider::class.java)
    }
  }

  @Test
  fun europeanTransactionRoundTripRequiresEur() {
    val transaction = EuropeanTransaction(
      id = "ept-10000",
      reference = "EU-10000",
      recipientId = "northline-studio",
      amount = MonetaryAmount(1_000_000, CurrencyCode.eur),
      provider = DynamicProvider.adyenCard,
      method = PaymentMethod.card,
      status = TransactionStatus.pending,
      note = "Corridor rehearsal",
      idempotencyKey = "idem-eur-1",
    )
    val json = mapper.writeValueAsString(transaction)
    assertTrue(json.contains("EUR"))
    val decoded = mapper.readValue(json, EuropeanPaymentTransaction::class.java)
    assertEquals(transaction, decoded)
    assertEquals("idem-eur-1", decoded.idempotencyKey)
    assertEquals(1_000_000, decoded.cachedRecord().minorUnits)

    assertThrows(IllegalArgumentException::class.java) {
      EuropeanPaymentTransaction(
        id = "bad",
        reference = "x",
        recipientId = "northline-studio",
        amount = MonetaryAmount(100, CurrencyCode.gbp),
        provider = DynamicProvider.worldpayBank,
        method = PaymentMethod.bank,
        status = TransactionStatus.completed,
      )
    }
  }

  @Test
  fun legacyCacheDefaultsToGbpStoreAndIsNotOverwritten() {
    val root = Files.createTempDirectory("meridian-cache").toFile()
    val legacy = """
      {
        "version": 1,
        "balance": 1248050,
        "transactions": [
          {
            "id": "txn-001",
            "reference": "REF-1",
            "recipientId": "birch-bloom",
            "name": "Birch & Bloom",
            "category": "Food & drink",
            "amount": 3500,
            "date": "2026-09-05",
            "provider": "worldpay",
            "method": "bank",
            "status": "completed",
            "note": "Breakfast"
          }
        ],
        "budgets": []
      }
    """.trimIndent()
    val legacyFile = java.io.File(root, "payments.json")
    val legacyBytes = legacy.toByteArray()
    legacyFile.writeBytes(legacyBytes)

    val cache = IsolatedPaymentCache(root)
    assertArrayEquals(legacyBytes, legacyFile.readBytes())
    val gbp = cache.gbpStore.load()
    assertEquals(1, gbp.size)
    assertEquals(3500, gbp[0].minorUnits)
    assertEquals(CurrencyCode.gbp, gbp[0].currency)
    assertEquals(ProviderId.worldpay, gbp[0].providerId)
    assertTrue(cache.eurStore.load().isEmpty())
    assertTrue(cache.gbpStore.paymentsFile.path.contains("GBPStore"))
    assertTrue(cache.eurStore.paymentsFile.path.contains("EURStore"))

    val gbpBytes = cache.gbpStore.readBytes()
    cache.eurStore.save(
      listOf(
        CachedPaymentRecord(
          id = "eur-1",
          minorUnits = 1,
          currency = CurrencyCode.eur,
          reference = "cent",
          recipientId = "northline-studio",
          providerId = ProviderId.adyen,
          method = PaymentMethod.card,
          status = TransactionStatus.pending,
          idempotencyKey = "idem-eur-1",
        ),
      ),
    )
    assertArrayEquals(gbpBytes, cache.gbpStore.readBytes())
    assertEquals(1, cache.eurStore.load().single().minorUnits)

    val replacement = """
      {"records":[{"id":"other","minorUnits":99,"currency":"GBP","reference":"","recipientId":"birch-bloom","providerId":"adyen","method":"card","status":"completed","note":"","idempotencyKey":""}]}
    """.trimIndent()
    cache.importCached(replacement.toByteArray())
    assertEquals("txn-001", cache.gbpStore.load().single().id)

    val beforeReject = cache.gbpStore.readBytes()
    val eurRecord = cache.eurStore.load().single()
    assertThrows(MeridianError.ValidationError::class.java) {
      cache.gbpStore.save(listOf(eurRecord))
    }
    assertArrayEquals(beforeReject, cache.gbpStore.readBytes())
  }

  @Test
  fun upsertRetainsIdempotencyKey() {
    val root = Files.createTempDirectory("meridian-key").toFile()
    val cache = IsolatedPaymentCache(root)
    cache.gbpStore.save(
      listOf(
        CachedPaymentRecord(
          id = "pay-1",
          minorUnits = 100,
          currency = CurrencyCode.gbp,
          reference = "held",
          recipientId = "birch-bloom",
          providerId = ProviderId.adyen,
          method = PaymentMethod.card,
          status = TransactionStatus.pending,
          idempotencyKey = "same-key",
        ),
      ),
    )
    cache.gbpStore.upsert(
      CachedPaymentRecord(
        id = "pay-1",
        minorUnits = 100,
        currency = CurrencyCode.gbp,
        reference = "held",
        recipientId = "birch-bloom",
        providerId = ProviderId.adyen,
        method = PaymentMethod.card,
        status = TransactionStatus.pending,
        idempotencyKey = "",
      ),
    )
    assertEquals("same-key", cache.gbpStore.load().single().idempotencyKey)
  }

  @Test
  fun eurRecordPlacedUnderGbpKeyIsRehomed() {
    val root = Files.createTempDirectory("meridian-split").toFile()
    val payload = """
      {"GBPStore":[{"id":"moved","minorUnits":1,"currency":"EUR","reference":"","recipientId":"northline-studio","providerId":"adyen","method":"card","status":"pending","note":"","idempotencyKey":"k"}]}
    """.trimIndent()
    java.io.File(root, "cache.json").writeText(payload)
    val cache = IsolatedPaymentCache(root)
    assertTrue(cache.gbpStore.load().isEmpty())
    assertEquals("moved", cache.eurStore.load().single().id)
    assertEquals(CurrencyCode.eur, cache.eurStore.load().single().currency)
  }

  @Test
  fun corruptStoreAndFractionalUnitsAreLeftUnchanged() {
    val root = Files.createTempDirectory("meridian-corrupt").toFile()
    val cache = IsolatedPaymentCache(root)
    cache.gbpStore.paymentsFile.writeBytes("not-json".toByteArray())
    val before = cache.gbpStore.readBytes()
    assertThrows(MeridianError::class.java) { cache.gbpStore.load() }
    assertArrayEquals(before, cache.gbpStore.readBytes())

    val clean = IsolatedPaymentCache(Files.createTempDirectory("meridian-fraction").toFile())
    val fraction = """
      [{"id":"bad","minorUnits":10.5,"currency":"GBP","providerId":"adyen","method":"card","status":"completed"}]
    """.trimIndent()
    assertThrows(MeridianError::class.java) { clean.importCached(fraction.toByteArray()) }
    assertTrue(clean.gbpStore.load().isEmpty())
    assertTrue(clean.eurStore.load().isEmpty())
  }
}
