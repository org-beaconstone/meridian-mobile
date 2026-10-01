package com.atlassian.meridian

import com.fasterxml.jackson.databind.DeserializationFeature
import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import java.net.URI
import java.net.URL
import java.net.URLEncoder
import java.util.Locale

/** Hard cap so a catalog response cannot be cached unbounded. */
internal const val MAX_CATALOG_BYTES = 256 * 1024

/** Capability token that forces fail-closed expiry even when the boolean is absent or false. */
internal const val LIVE_ELIGIBILITY_CAPABILITY = "live_eligibility"

internal val catalogMapper: ObjectMapper = ObjectMapper().registerKotlinModule().apply {
  configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false)
}

/**
 * Cache and request key. Currency is GBP only; amounts elsewhere stay integer pence.
 * Provider ids are open strings. The native baseline remains Adyen card and Worldpay bank.
 */
data class CatalogScope(
  val accountScope: String,
  val corridor: String,
  val currency: String,
) {
  val storageKey: String = "$accountScope|$corridor|$currency"

  companion object {
    private val SCOPE = Regex("[A-Za-z0-9._:-]{1,64}")
    private val CORRIDOR = Regex("[A-Z0-9_-]{2,16}")

    fun parse(accountScope: String, corridor: String, currency: String): CatalogScope {
      val scope = accountScope.trim()
      val corridorNorm = corridor.trim().uppercase(Locale.ROOT)
      val currencyNorm = currency.trim().uppercase(Locale.ROOT)
      if (!SCOPE.matches(scope)) {
        throw MeridianError.ValidationError("Account scope is invalid")
      }
      if (!CORRIDOR.matches(corridorNorm)) {
        throw MeridianError.ValidationError("Corridor is invalid")
      }
      if (currencyNorm != "GBP") {
        throw MeridianError.ValidationError("Only GBP payment catalogs are supported")
      }
      return CatalogScope(scope, corridorNorm, currencyNorm)
    }
  }
}

/**
 * Open payment-method record. Unknown JSON attributes are ignored so older builds keep decoding.
 * [method] and [provider] stay strings so a new value does not crash a closed enum.
 */
data class PaymentMethodDescriptor(
  val id: String,
  val method: String,
  val provider: String,
  val displayName: String,
  val currency: String,
  val corridor: String,
  val accountScope: String,
  val capabilities: List<String>,
  val requiresLiveEligibility: Boolean,
  val ttlSeconds: Int,
  val enabled: Boolean,
)

data class PaymentMethodsCatalog(
  val accountScope: String,
  val corridor: String,
  val currency: String,
  val ttlSeconds: Int,
  val methods: List<PaymentMethodDescriptor>,
)

data class PaymentMethodsFetch(
  val catalog: PaymentMethodsCatalog,
  val rawJson: String,
)

/**
 * `GET /api/v2/payment-methods` against the same origin as an `/api/v1` base URL.
 */
fun paymentMethodsUrl(baseUrl: String, scope: CatalogScope): URL {
  var normalized = baseUrl.trim().removeSuffix("/")
  val marker = when {
    normalized.endsWith("/api/v1") -> "/api/v1"
    normalized.endsWith("/api/v2") -> "/api/v2"
    else -> null
  }
  if (marker != null) {
    normalized = normalized.removeSuffix(marker).removeSuffix("/")
  }
  if (!normalized.startsWith("http://") && !normalized.startsWith("https://")) {
    throw MeridianError.InvalidURL("Invalid URL")
  }
  val query = listOf(
    "accountScope" to scope.accountScope,
    "corridor" to scope.corridor,
    "currency" to scope.currency,
  ).joinToString("&") { (name, value) ->
    "$name=${URLEncoder.encode(value, "UTF-8")}"
  }
  return URI.create("$normalized/api/v2/payment-methods?$query").toURL()
}

/**
 * Deserialize a catalog. Extra attributes are ignored. A single bad descriptor is skipped
 * so one unknown shape cannot take down the rest of the list.
 */
fun parsePaymentMethodsCatalog(rawJson: String, expected: CatalogScope): PaymentMethodsCatalog {
  if (rawJson.toByteArray(Charsets.UTF_8).size > MAX_CATALOG_BYTES) {
    throw MeridianError.ValidationError("Payment method catalog is too large")
  }
  val root = try {
    catalogMapper.readTree(rawJson)
  } catch (error: Exception) {
    throw MeridianError.DecodingError("Payment method catalog is not valid JSON", error)
  }
  if (root == null || !root.isObject) {
    throw MeridianError.DecodingError("Payment method catalog must be an object")
  }

  val accountScope = requiredText(root, "accountScope")
    ?: throw MeridianError.DecodingError("Payment method catalog is missing account scope")
  if (accountScope != expected.accountScope) {
    throw MeridianError.ValidationError("Payment method catalog account scope does not match the request")
  }

  val corridor = root.get("corridor")?.takeIf { it.isTextual }?.asText()?.trim()?.uppercase(Locale.ROOT)
    ?: throw MeridianError.DecodingError("Payment method catalog is missing corridor")
  if (corridor != expected.corridor) {
    throw MeridianError.ValidationError("Payment method catalog corridor does not match the request")
  }

  val currency = root.get("currency")?.takeIf { it.isTextual }?.asText()?.trim()?.uppercase(Locale.ROOT)
    ?: throw MeridianError.DecodingError("Payment method catalog is missing currency")
  if (currency != expected.currency) {
    throw MeridianError.ValidationError("Only GBP payment catalogs are supported")
  }

  val ttlSeconds = positiveInt(root.get("ttlSeconds"))
    ?: throw MeridianError.DecodingError("Payment method catalog TTL is invalid")

  val methodsNode = root.get("methods")
  if (methodsNode == null || !methodsNode.isArray) {
    throw MeridianError.DecodingError("Payment method catalog is missing methods")
  }

  val methods = mutableListOf<PaymentMethodDescriptor>()
  for (item in methodsNode) {
    parseDescriptor(item, expected, ttlSeconds)?.let { methods.add(it) }
  }

  return PaymentMethodsCatalog(
    accountScope = accountScope,
    corridor = corridor,
    currency = currency,
    ttlSeconds = ttlSeconds,
    methods = methods,
  )
}

private fun parseDescriptor(
  item: JsonNode,
  expected: CatalogScope,
  catalogTtl: Int,
): PaymentMethodDescriptor? {
  if (!item.isObject) return null
  val id = requiredText(item, "id") ?: return null
  val method = requiredText(item, "method") ?: return null
  val provider = requiredText(item, "provider") ?: return null
  val displayName = requiredText(item, "displayName") ?: return null

  val currency = if (item.has("currency")) {
    val value = item.get("currency").takeIf { it.isTextual }?.asText()?.trim()?.uppercase(Locale.ROOT)
      ?: return null
    if (value != expected.currency) return null
    value
  } else {
    expected.currency
  }

  val corridor = if (item.has("corridor")) {
    val value = item.get("corridor").takeIf { it.isTextual }?.asText()?.trim()?.uppercase(Locale.ROOT)
      ?: return null
    if (value != expected.corridor) return null
    value
  } else {
    expected.corridor
  }

  val accountScope = if (item.has("accountScope")) {
    val value = requiredText(item, "accountScope") ?: return null
    if (value != expected.accountScope) return null
    value
  } else {
    expected.accountScope
  }

  val capabilities = if (item.has("capabilities")) {
    val node = item.get("capabilities")
    if (!node.isArray) return null
    node.mapNotNull { child -> child.takeIf { it.isTextual }?.asText()?.trim()?.takeIf { it.isNotEmpty() } }
  } else {
    emptyList()
  }

  val liveFlag = if (item.has("requiresLiveEligibility")) {
    booleanValue(item.get("requiresLiveEligibility")) ?: return null
  } else {
    false
  }
  val requiresLiveEligibility = liveFlag || capabilities.any { it == LIVE_ELIGIBILITY_CAPABILITY }

  val ttlSeconds = if (item.has("ttlSeconds")) {
    positiveInt(item.get("ttlSeconds")) ?: return null
  } else {
    catalogTtl
  }

  val enabled = if (item.has("enabled")) {
    booleanValue(item.get("enabled")) ?: return null
  } else {
    true
  }

  return PaymentMethodDescriptor(
    id = id,
    method = method,
    provider = provider,
    displayName = displayName,
    currency = currency,
    corridor = corridor,
    accountScope = accountScope,
    capabilities = capabilities,
    requiresLiveEligibility = requiresLiveEligibility,
    ttlSeconds = ttlSeconds,
    enabled = enabled,
  )
}

private fun requiredText(node: JsonNode, field: String): String? {
  val value = node.get(field) ?: return null
  if (!value.isTextual) return null
  val text = value.asText().trim()
  return text.takeIf { it.isNotEmpty() }
}

private fun positiveInt(node: JsonNode?): Int? {
  if (node == null || node.isNull || !node.isIntegralNumber) return null
  val value = node.longValue()
  if (value <= 0L || value > Int.MAX_VALUE) return null
  return value.toInt()
}

private fun booleanValue(node: JsonNode?): Boolean? {
  if (node == null || !node.isBoolean) return null
  return node.booleanValue()
}
