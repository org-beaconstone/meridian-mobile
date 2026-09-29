package com.atlassian.meridian

import com.fasterxml.jackson.core.JsonGenerator
import com.fasterxml.jackson.core.JsonParser
import com.fasterxml.jackson.databind.DeserializationContext
import com.fasterxml.jackson.databind.JsonDeserializer
import com.fasterxml.jackson.databind.JsonSerializer
import com.fasterxml.jackson.databind.SerializerProvider
import com.fasterxml.jackson.databind.annotation.JsonDeserialize
import com.fasterxml.jackson.databind.annotation.JsonSerialize
import kotlin.math.abs

/**
 * ISO currency codes the mobile SDK can store.
 * Live rehearsal payments remain integer GBP pence. EUR values stay in EURStore
 * and are not submitted to the Java API, which still accepts GBP minor units only.
 */
@JsonSerialize(using = CurrencyCodeSerializer::class)
@JsonDeserialize(using = CurrencyCodeDeserializer::class)
enum class CurrencyCode(val wire: String) {
  gbp("GBP"),
  eur("EUR");

  companion object {
    fun fromWire(value: String): CurrencyCode =
      entries.firstOrNull { it.wire == value }
        ?: throw IllegalArgumentException("Unknown currency code")
  }
}

class CurrencyCodeSerializer : JsonSerializer<CurrencyCode>() {
  override fun serialize(value: CurrencyCode, gen: JsonGenerator, serializers: SerializerProvider) {
    gen.writeString(value.wire)
  }
}

class CurrencyCodeDeserializer : JsonDeserializer<CurrencyCode>() {
  override fun deserialize(parser: JsonParser, context: DeserializationContext): CurrencyCode =
    CurrencyCode.fromWire(parser.valueAsString ?: parser.text)
}

/** Integer minor units: pence for GBP, cents for EUR. */
data class MonetaryAmount(
  val minorUnits: Int,
  val currency: CurrencyCode,
) {
  fun formatted(): String = formatMonetaryAmount(this)
}

/**
 * Baseline provider record. Only Adyen (card) and Worldpay (bank) exist.
 * Currency support on the baseline is GBP; no European provider is contracted.
 */
data class DynamicProvider(
  val id: ProviderId,
  val name: String,
  val methods: List<PaymentMethod>,
  val currencies: List<CurrencyCode>,
) {
  companion object {
    val adyenCard = DynamicProvider(
      ProviderId.adyen,
      "Adyen",
      listOf(PaymentMethod.card),
      listOf(CurrencyCode.gbp),
    )
    val worldpayBank = DynamicProvider(
      ProviderId.worldpay,
      "Worldpay",
      listOf(PaymentMethod.bank),
      listOf(CurrencyCode.gbp),
    )
    val baseline = listOf(adyenCard, worldpayBank)
  }
}

/**
 * EUR payment record. EuropeanTransaction is the same type.
 * Amount currency is EUR. The provider id is still the Adyen/Worldpay baseline.
 */
data class EuropeanPaymentTransaction(
  val id: String,
  val reference: String,
  val recipientId: String,
  val amount: MonetaryAmount,
  val provider: DynamicProvider,
  val method: PaymentMethod,
  val status: TransactionStatus,
  val note: String = "",
  val idempotencyKey: String = "",
) {
  init {
    require(amount.currency == CurrencyCode.eur) {
      "EuropeanPaymentTransaction requires EUR"
    }
  }

  fun cachedRecord(): CachedPaymentRecord = CachedPaymentRecord(
    id = id,
    minorUnits = amount.minorUnits,
    currency = amount.currency,
    reference = reference,
    recipientId = recipientId,
    providerId = provider.id,
    method = method,
    status = status,
    note = note,
    idempotencyKey = idempotencyKey,
  )
}

typealias EuropeanTransaction = EuropeanPaymentTransaction

/** 0 -> "£0.00" / "€0.00", 1 -> "£0.01" / "€0.01", 1_000_000 EUR -> "€10,000.00". */
fun formatMonetaryAmount(amount: MonetaryAmount): String {
  val negative = amount.minorUnits < 0
  val units = abs(amount.minorUnits)
  val major = units / 100
  val minor = units % 100
  val symbol = when (amount.currency) {
    CurrencyCode.gbp -> "£"
    CurrencyCode.eur -> "€"
  }
  val sign = if (negative) "-" else ""
  return "$sign$symbol${groupedMajorUnits(major)}.${minor.toString().padStart(2, '0')}"
}

internal fun groupedMajorUnits(value: Int): String {
  val digits = value.toString()
  val grouped = StringBuilder()
  digits.reversed().forEachIndexed { index, character ->
    if (index != 0 && index % 3 == 0) grouped.append(',')
    grouped.append(character)
  }
  return grouped.reverse().toString()
}
