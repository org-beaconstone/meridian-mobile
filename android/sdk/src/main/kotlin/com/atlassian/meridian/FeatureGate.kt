package com.atlassian.meridian

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper

const val MOBILE_EU_PAYMENTS_FLAG = "enable_mobile_eu_payments"

enum class CurrencyCode { GBP, EUR }

/** A customer-facing rail. Only Adyen card and Worldpay bank are constructed. */
data class PaymentRail(
  val id: String,
  val provider: ProviderId,
  val method: PaymentMethod,
  val currency: CurrencyCode,
  val label: String,
)

data class PaymentSurface(
  val flagEnabled: Boolean,
  val dynamicCatalogActive: Boolean,
  val usingCachedGbp: Boolean,
  val currencies: List<CurrencyCode>,
  val rails: List<PaymentRail>,
)

data class ResolvedSurface(
  val surface: PaymentSurface,
  val cachedGbp: List<PaymentRail>,
)

data class PaymentSelection(
  val currency: CurrencyCode,
  val railId: String,
  val reviewing: Boolean,
)

val gbpBaseline: List<PaymentRail> = listOf(
  PaymentRail("adyen-card-gbp", ProviderId.adyen, PaymentMethod.card, CurrencyCode.GBP, "Debit card · Adyen"),
  PaymentRail("worldpay-bank-gbp", ProviderId.worldpay, PaymentMethod.bank, CurrencyCode.GBP, "Bank payment · Worldpay"),
)

private val flagMapper = ObjectMapper()

/** Boolean true or the string "true" enables the flag. Every other payload disables it. */
fun evaluateMobileEuPaymentsFlag(body: String): Boolean {
  val node = try {
    flagMapper.readTree(body)
  } catch (_: Exception) {
    return false
  }
  if (node == null || !node.isObject) return false
  val direct = node.get(MOBILE_EU_PAYMENTS_FLAG)
  if (direct != null && !direct.isNull) return coerceFlag(direct)
  val nested = node.get("flags")?.get(MOBILE_EU_PAYMENTS_FLAG)
  if (nested != null && !nested.isNull) return coerceFlag(nested)
  return false
}

private fun coerceFlag(node: JsonNode): Boolean {
  if (node.isBoolean) return node.booleanValue()
  if (node.isTextual) return node.asText().equals("true", ignoreCase = true)
  return false
}

/**
 * Flag off keeps the cached GBP Adyen/Worldpay list and hides EUR.
 * Flag on may relabel those two rails from the catalog and add EUR.
 * The rail list is never empty, and no other provider is shown.
 */
fun resolvePaymentSurface(
  flagEnabled: Boolean,
  providers: List<Provider>?,
  cachedGbp: List<PaymentRail>,
): ResolvedSurface {
  val cached = sanitizeGbp(cachedGbp)
  if (!flagEnabled) {
    return ResolvedSurface(
      PaymentSurface(
        flagEnabled = false,
        dynamicCatalogActive = false,
        usingCachedGbp = true,
        currencies = listOf(CurrencyCode.GBP),
        rails = cached,
      ),
      cached,
    )
  }

  val gbp = cached.toMutableList()
  val eur = mutableListOf<PaymentRail>()
  var recognized = 0
  var relabelled = false
  val seen = mutableSetOf<ProviderId>()

  for (provider in providers.orEmpty()) {
    val pair = recognizedPair(provider) ?: continue
    if (!seen.add(pair.provider)) continue
    recognized += 1
    val name = displayName(provider)
    if (offers(provider, "GBP")) {
      gbp[pair.index] = PaymentRail(pair.gbpId, pair.provider, pair.method, CurrencyCode.GBP, gbpLabel(name, pair.method))
      relabelled = true
    }
    if (offers(provider, "EUR")) {
      eur += PaymentRail(pair.eurId, pair.provider, pair.method, CurrencyCode.EUR, eurLabel(name, pair.method))
    }
  }

  if (recognized == 0) {
    eur += cached.map { eurVersion(it) }
  }

  val currencies = if (eur.isEmpty()) listOf(CurrencyCode.GBP) else listOf(CurrencyCode.GBP, CurrencyCode.EUR)
  return ResolvedSurface(
    PaymentSurface(
      flagEnabled = true,
      dynamicCatalogActive = recognized > 0,
      usingCachedGbp = !relabelled,
      currencies = currencies,
      rails = gbp + eur,
    ),
    gbp,
  )
}

fun reconcileSelection(
  surface: PaymentSurface,
  currency: CurrencyCode,
  railId: String,
  reviewing: Boolean,
): PaymentSelection {
  val rails = surface.rails.ifEmpty { gbpBaseline }
  val allowed = if (surface.currencies.contains(currency)) currency else CurrencyCode.GBP
  val pool = rails.filter { it.currency == allowed }
  val choices = pool.ifEmpty { rails }
  val kept = choices.firstOrNull { it.id == railId }
  val chosen = kept ?: choices.first()
  val stillReviewing = reviewing && kept != null && allowed == currency
  return PaymentSelection(allowed, chosen.id, stillReviewing)
}

private data class RecognizedPair(
  val provider: ProviderId,
  val method: PaymentMethod,
  val index: Int,
  val gbpId: String,
  val eurId: String,
)

private fun recognizedPair(provider: Provider): RecognizedPair? {
  val methods = provider.methods.map { it.lowercase() }
  return when (provider.id.lowercase()) {
    "adyen" -> if (methods.contains("card")) {
      RecognizedPair(ProviderId.adyen, PaymentMethod.card, 0, "adyen-card-gbp", "adyen-card-eur")
    } else {
      null
    }
    "worldpay" -> if (methods.contains("bank")) {
      RecognizedPair(ProviderId.worldpay, PaymentMethod.bank, 1, "worldpay-bank-gbp", "worldpay-bank-eur")
    } else {
      null
    }
    else -> null
  }
}

private fun sanitizeGbp(rails: List<PaymentRail>): List<PaymentRail> {
  val adyen = rails.firstOrNull { it.provider == ProviderId.adyen && it.method == PaymentMethod.card && it.currency == CurrencyCode.GBP }
  val worldpay = rails.firstOrNull { it.provider == ProviderId.worldpay && it.method == PaymentMethod.bank && it.currency == CurrencyCode.GBP }
  return listOf(adyen ?: gbpBaseline[0], worldpay ?: gbpBaseline[1])
}

private fun displayName(provider: Provider): String {
  val trimmed = provider.name.trim()
  if (trimmed.isNotEmpty()) return trimmed
  return if (provider.id.equals("adyen", ignoreCase = true)) "Adyen" else "Worldpay"
}

private fun offers(provider: Provider, currency: String): Boolean {
  val currencies = provider.currencies.orEmpty().map { it.uppercase() }
  if (currencies.isNotEmpty()) return currencies.contains(currency)
  if (currency == "GBP") return true
  val regions = provider.regions.orEmpty().map { it.uppercase() }
  if (regions.isNotEmpty()) return regions.any { it == "EU" || it == "EEA" || it == "EUR" }
  return true
}

private fun gbpLabel(name: String, method: PaymentMethod): String =
  if (method == PaymentMethod.card) "Debit card · $name" else "Bank payment · $name"

private fun eurLabel(name: String, method: PaymentMethod): String = "${gbpLabel(name, method)} · EUR"

private fun eurVersion(rail: PaymentRail): PaymentRail {
  val name = if (rail.provider == ProviderId.adyen) "Adyen" else "Worldpay"
  val id = if (rail.provider == ProviderId.adyen) "adyen-card-eur" else "worldpay-bank-eur"
  return PaymentRail(id, rail.provider, rail.method, CurrencyCode.EUR, eurLabel(name, rail.method))
}
