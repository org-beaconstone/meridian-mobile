package com.atlassian.meridian

import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

enum class CatalogOrigin {
  network,
  cache,
}

data class CatalogLoad(
  val catalog: CatalogResponse?,
  val origin: CatalogOrigin?,
)

/**
 * Keeps checkout on Adyen card and Worldpay bank, GBP only.
 * Unknown catalog providers are dropped and are not stored.
 */
fun projectBaselineCatalog(raw: CatalogResponse): CatalogResponse {
  val projected = mutableListOf<DynamicProvider>()
  for (provider in raw.providers) {
    val baseline = baselineProvider(provider) ?: continue
    if (projected.any { it.id == baseline.id }) continue
    projected.add(baseline)
  }
  projected.sortBy { providerRank(it.id) }
  return raw.copy(providers = projected)
}

fun catalogFailureUsesCache(error: Throwable): Boolean {
  if (error is SocketTimeoutException) return true
  if (error is UnknownHostException || error is ConnectException || error is NoRouteToHostException) return true
  if (error is SocketException) return true
  if (error is MeridianError.HttpError) {
    return error.statusCode == 408 || error.statusCode in 500..599
  }
  if (error is MeridianError.NetworkError) return true
  return false
}

private fun providerRank(id: String): Int = when (id) {
  ProviderId.adyen.name -> 0
  ProviderId.worldpay.name -> 1
  else -> 2
}

private fun baselineProvider(provider: DynamicProvider): DynamicProvider? {
  val id = provider.id.trim().lowercase()
  val allowed: String
  val name: String
  val description: String
  when (id) {
    ProviderId.adyen.name -> {
      allowed = PaymentMethod.card.name
      name = "Adyen"
      description = "Card processor"
    }
    ProviderId.worldpay.name -> {
      allowed = PaymentMethod.bank.name
      name = "Worldpay"
      description = "Bank payment processor"
    }
    else -> return null
  }

  val parsedMethods = provider.methods.mapNotNull { normalizeCatalogMethod(it) }
  if (parsedMethods.isNotEmpty() && allowed !in parsedMethods) return null

  val currencies = gbpCurrencies(provider.currencies)
  if (currencies != listOf("GBP")) return null

  val corridors = baselineCorridors(provider.corridors, id, allowed)
  if (corridors.isEmpty()) return null

  return DynamicProvider(
    id = id,
    name = name,
    description = description,
    methods = listOf(allowed),
    currencies = currencies,
    corridors = corridors,
  )
}

private fun gbpCurrencies(raw: List<String>): List<String> {
  val codes = raw.map { it.trim().uppercase() }.filter { it.isNotEmpty() }
  if (codes.isEmpty()) return listOf("GBP")
  return if ("GBP" in codes) listOf("GBP") else emptyList()
}

private fun baselineCorridors(
  raw: List<PaymentCorridor>,
  providerId: String,
  allowedMethod: String,
): List<PaymentCorridor> {
  val seen = mutableSetOf<String>()
  val kept = mutableListOf<PaymentCorridor>()
  for (corridor in raw) {
    if (normalizeCatalogMethod(corridor.method) != allowedMethod) continue
    val currency = corridor.currency.trim().uppercase()
    if (currency.isNotEmpty() && currency != "GBP") continue
    val fallback = "$providerId-$allowedMethod-gbp"
    val identifier = safeToken(corridor.id, fallback, seen)
    kept.add(
      PaymentCorridor(
        id = identifier,
        method = allowedMethod,
        currency = "GBP",
        country = corridorCountry(corridor.country),
      )
    )
  }
  if (kept.isEmpty()) {
    val identifier = safeToken("", "$providerId-$allowedMethod-gbp", seen)
    kept.add(PaymentCorridor(id = identifier, method = allowedMethod, currency = "GBP", country = "GB"))
  }
  return kept
}

private fun corridorCountry(raw: String): String {
  val trimmed = raw.trim()
  if (trimmed.isEmpty()) return "GB"
  if (trimmed.length == 2) return trimmed.uppercase()
  return trimmed.take(32)
}

private fun safeToken(raw: String, fallback: String, seen: MutableSet<String>): String {
  val trimmed = raw.trim()
  val safe = trimmed.isNotEmpty() && trimmed.length <= 64 && trimmed.all { it.isLetterOrDigit() || it == '-' || it == '_' }
  var candidate = if (safe) trimmed else fallback
  if (candidate.isEmpty()) candidate = fallback
  var unique = candidate
  var suffix = 2
  while (!seen.add(unique)) {
    unique = "$candidate-$suffix"
    suffix += 1
  }
  return unique
}

private fun normalizeCatalogMethod(raw: String): String? {
  val value = raw.trim().lowercase().replace('-', '_').replace(' ', '_')
  return when (value) {
    "card", "debit_card" -> PaymentMethod.card.name
    "bank", "bank_transfer", "banktransfer" -> PaymentMethod.bank.name
    else -> null
  }
}
