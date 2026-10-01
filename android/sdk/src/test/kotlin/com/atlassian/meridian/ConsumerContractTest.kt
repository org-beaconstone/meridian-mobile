package com.atlassian.meridian

import com.fasterxml.jackson.annotation.JsonIgnoreProperties
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ConsumerContractTest {
  private val mapper = ObjectMapper().registerKotlinModule()

  @Test
  fun consumerExpectationsMatchFixtures() {
    val root = contractsDirectory()
    val document = mapper.readValue(File(root, "consumer-expectations.json"), ExpectationFile::class.java)
    assertEquals("meridian-mobile", document.consumer)
    for (item in document.cases) {
      val json = File(root, item.fixture).readText()
      val result = when (item.kind) {
        "catalog" -> ConsumerContract.evaluateCatalog(json)
        "intent" -> ConsumerContract.evaluatePaymentIntent(json)
        "transaction" -> ConsumerContract.evaluateTransaction(json)
        else -> error("unknown kind ${item.kind}")
      }
      if (item.expect == "accepted") {
        assertTrue(item.fixture, result.accepted && result.code == "OK")
        item.currency?.let { assertEquals(item.fixture, it, result.currency) }
        item.legacy?.let { assertEquals(item.fixture, it, result.legacyShape) }
        item.amountMinor?.let { assertEquals(item.fixture, it, result.amountMinor) }
        item.provider?.let {
          assertTrue(item.fixture, result.provider == it || result.providerIds.contains(it))
        }
      } else {
        assertFalse(item.fixture, result.accepted)
        assertEquals(item.fixture, item.expect, result.code)
        item.detailContains?.let { assertTrue(result.detail, result.detail.contains(it)) }
      }
    }
  }

  @Test
  fun legacyAndObjectAmountsMatch() {
    val root = contractsDirectory()
    val legacy = ConsumerContract.evaluatePaymentIntent(File(root, "payment-intent-legacy.json").readText())
    val objectAmount = ConsumerContract.evaluatePaymentIntent(File(root, "payment-intent-gbp-object.json").readText())
    assertTrue(legacy.accepted && objectAmount.accepted)
    assertEquals(2599, legacy.amountMinor)
    assertEquals(2599, objectAmount.amountMinor)
    assertEquals(true, legacy.legacyShape)
    assertEquals(false, objectAmount.legacyShape)
  }

  @Test
  fun outboundStaysIntegerPence() {
    val json = ConsumerContract.encodeLegacyPaymentIntent("northline-studio", 2599, "card", "Desk lamp", "success")
    val node = mapper.readTree(json)
    assertEquals(2599, node.get("amountMinor").intValue())
    assertNull(node.get("amount"))
    assertEquals("card", node.get("method").asText())
  }

  @Test
  fun codableLegacyCatalogValidates() {
    val catalog = mapper.readValue(File(contractsDirectory(), "catalog-legacy.json"), CatalogResponse::class.java)
    catalog.assertConsumerContract()
    assertEquals("GBP", catalog.currency)
    assertEquals(2, catalog.minorUnit)
  }

  @Test
  fun codableGbpCatalogValidates() {
    val catalog = mapper.readValue(File(contractsDirectory(), "catalog-gbp-object.json"), CatalogResponse::class.java)
    catalog.assertConsumerContract()
    assertEquals("GBP", catalog.currency)
  }

  @Test
  fun codableEurCatalogRejected() {
    val catalog = mapper.readValue(File(contractsDirectory(), "catalog-eur.json"), CatalogResponse::class.java)
    val error = assertThrows(ContractRejection::class.java) { catalog.assertConsumerContract() }
    assertEquals("UNSUPPORTED_CURRENCY", error.code)
  }

  @Test
  fun codableEmptyIdRejected() {
    val catalog = mapper.readValue(File(contractsDirectory(), "catalog-empty-id.json"), CatalogResponse::class.java)
    val error = assertThrows(ContractRejection::class.java) { catalog.assertConsumerContract() }
    assertTrue(error.message?.contains("empty_recipient_id") == true)
  }

  @Test
  fun codableTransactionsAcceptBothShapes() {
    val root = contractsDirectory()
    val legacy = mapper.readValue(File(root, "transaction-legacy.json"), Transaction::class.java)
    val objectAmount = mapper.readValue(File(root, "transaction-gbp-object.json"), Transaction::class.java)
    assertEquals(3500, legacy.amount)
    assertEquals(3500, objectAmount.amount)
  }

  @Test
  fun codableEurTransactionRejected() {
    val json = """
      {"id":"txn","reference":"R","recipientId":"northline-studio","name":"Northline Studio","category":"Shopping","amount":{"minor":3500,"currency":"EUR"},"date":"2026-09-05","provider":"adyen","method":"card","status":"completed","note":"Lamp"}
    """.trimIndent()
    val error = assertThrows(Exception::class.java) { mapper.readValue(json, Transaction::class.java) }
    assertTrue(error.message?.contains("UNSUPPORTED_CURRENCY") == true)
  }

  @Test
  fun noteTooLongRejected() {
    val note = "a".repeat(201)
    val result = ConsumerContract.evaluatePaymentIntent(
      """{"recipientId":"northline-studio","amountMinor":100,"method":"card","note":"$note","scenario":"success"}""",
    )
    assertFalse(result.accepted)
    assertEquals("MALFORMED_INTENT", result.code)
    assertEquals("note_too_long", result.detail)
  }
}

@JsonIgnoreProperties(ignoreUnknown = true)
data class ExpectationFile(val consumer: String, val cases: List<ExpectationCase>)

@JsonIgnoreProperties(ignoreUnknown = true)
data class ExpectationCase(
  val fixture: String,
  val kind: String,
  val expect: String,
  val currency: String? = null,
  val legacy: Boolean? = null,
  val amountMinor: Int? = null,
  val provider: String? = null,
  val detailContains: String? = null,
)

fun contractsDirectory(): File {
  var dir: File? = File(System.getProperty("user.dir")).absoluteFile
  while (dir != null) {
    val candidate = File(dir, "contracts")
    if (candidate.isDirectory) return candidate
    dir = dir.parentFile
  }
  error("contracts directory not found from ${System.getProperty("user.dir")}")
}
