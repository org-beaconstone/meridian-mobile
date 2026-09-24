package com.atlassian.meridian

import java.util.Locale
import java.util.logging.Level
import java.util.logging.Logger

/**
 * Config-driven payment methods resolved from meridian-api `GET /catalog`.
 *
 * The baseline registry is Adyen card and Worldpay bank. Method ids are
 * `adyen_card` and `worldpay_bank`. `POST /payments` still sends the contract
 * method `card` or `bank` so idempotency payloads stay stable.
 */
data class PaymentMethodOption(
  val id: String,
  val displayLabel: String,
  val providerName: String,
  val wireMethod: String,
) {
  fun pickerLabel(): String = "$displayLabel · $providerName"
}

object ProviderCatalogFlag {
  /**
   * Default off. `-Dmeridian.catalog.configDriven=true` or
   * `MERIDIAN_CATALOG_CONFIG_DRIVEN=true` enables the catalog picker.
   * A system property wins when it is present, including an explicit false.
   */
  fun enabled(): Boolean {
    val property = System.getProperty("meridian.catalog.configDriven")
    if (property != null) return property.equals("true", ignoreCase = true)
    val env = System.getenv("MERIDIAN_CATALOG_CONFIG_DRIVEN")
    return env?.equals("true", ignoreCase = true) == true
  }
}

object ProviderCatalog {
  const val ADYEN_CARD = "adyen_card"
  const val WORLDPAY_BANK = "worldpay_bank"
  const val DEFAULT_TTL_MILLIS = 30_000L

  /** Flag-off picker. Ids match the historical `PaymentMethod` enum names. */
  fun hardcodedPicker(): List<PaymentMethodOption> = listOf(
    PaymentMethodOption(id = "card", displayLabel = "Debit card", providerName = "Adyen", wireMethod = "card"),
    PaymentMethodOption(id = "bank", displayLabel = "Bank payment", providerName = "Worldpay", wireMethod = "bank"),
  )

  /** Used only when the flag is on and no last-known-good catalog exists. */
  fun safeDefault(): List<PaymentMethodOption> = listOf(
    PaymentMethodOption(ADYEN_CARD, "Debit card", "Adyen", "card"),
    PaymentMethodOption(WORLDPAY_BANK, "Bank payment", "Worldpay", "bank"),
  )

  fun parse(catalog: CatalogResponse): List<PaymentMethodOption> {
    val options = LinkedHashMap<String, PaymentMethodOption>()
    for (provider in catalog.providers) {
      for (method in provider.methods) {
        val option = optionFor(provider.id, provider.name, method) ?: continue
        options.putIfAbsent(option.id, option)
      }
    }
    return options.values.toList()
  }

  fun wireMethod(methodId: String): String = when (methodId.trim()) {
    "card", ADYEN_CARD -> "card"
    "bank", WORLDPAY_BANK -> "bank"
    else -> throw MeridianError.ValidationError("Unknown payment method id")
  }

  fun retainSelection(selectedId: String, options: List<PaymentMethodOption>): String {
    if (options.any { it.id == selectedId }) return selectedId
    return options.firstOrNull()?.id ?: selectedId
  }

  private fun optionFor(providerId: String, providerName: String, method: String): PaymentMethodOption? {
    val name = providerName.trim()
    return when (providerId to method) {
      "adyen" to "card" -> PaymentMethodOption(
        id = ADYEN_CARD,
        displayLabel = "Debit card",
        providerName = name.ifEmpty { "Adyen" },
        wireMethod = "card",
      )
      "worldpay" to "bank" -> PaymentMethodOption(
        id = WORLDPAY_BANK,
        displayLabel = "Bank payment",
        providerName = name.ifEmpty { "Worldpay" },
        wireMethod = "bank",
      )
      else -> null
    }
  }
}

/**
 * In-memory catalog cache. Expired entries stay available as last-known-good.
 */
class ProviderCatalogCache(
  private val ttlMillis: Long,
  private val clock: () -> Long,
) {
  private data class Snapshot(val options: List<PaymentMethodOption>, val storedAtMillis: Long)
  private val lock = Any()
  private var snapshot: Snapshot? = null

  fun fresh(): List<PaymentMethodOption>? = synchronized(lock) {
    val current = snapshot ?: return null
    if (clock() - current.storedAtMillis < ttlMillis) current.options else null
  }

  fun lastKnownGood(): List<PaymentMethodOption>? = synchronized(lock) { snapshot?.options }

  fun store(options: List<PaymentMethodOption>) = synchronized(lock) {
    snapshot = Snapshot(options.toList(), clock())
  }
}

class CatalogFetchMetrics {
  private val successCount = java.util.concurrent.atomic.AtomicLong()
  private val failureCount = java.util.concurrent.atomic.AtomicLong()
  private val fallbackCount = java.util.concurrent.atomic.AtomicLong()
  private val logger = Logger.getLogger(LOGGER_NAME).also { it.level = Level.INFO }

  fun successCount(): Long = successCount.get()
  fun failureCount(): Long = failureCount.get()
  fun fallbackCount(): Long = fallbackCount.get()

  fun recordSuccess() {
    val success = successCount.incrementAndGet()
    log("success", success, failureCount.get(), fallbackCount.get(), null, null)
  }

  fun recordFailure(detail: String, correlationId: String?) {
    val failure = failureCount.incrementAndGet()
    log("failure", successCount.get(), failure, fallbackCount.get(), correlationId, detail)
  }

  fun recordFallback(correlationId: String?) {
    val fallback = fallbackCount.incrementAndGet()
    log("fallback", successCount.get(), failureCount.get(), fallback, correlationId, "last-known-good")
  }

  fun recordBaseline(correlationId: String?) {
    log("baseline", successCount.get(), failureCount.get(), fallbackCount.get(), correlationId, "no last-known-good")
  }

  private fun log(
    result: String,
    success: Long,
    failure: Long,
    fallback: Long,
    correlationId: String?,
    detail: String?,
  ) {
    val correlation = correlationId?.takeIf { it.isNotBlank() } ?: "-"
    val safeDetail = detail?.replace(Regex("\\s+"), " ")?.take(300) ?: "-"
    logger.info(
      "catalog_fetch result=$result successCount=$success failureCount=$failure " +
        "fallbackCount=$fallback successRate=${rate(success, success + failure)} " +
        "fallbackRate=${rate(fallback, failure)} correlationId=$correlation detail=$safeDetail"
    )
  }

  private fun rate(numerator: Long, denominator: Long): String {
    if (denominator <= 0L) return "0.000"
    return String.format(Locale.US, "%.3f", numerator.toDouble() / denominator.toDouble())
  }

  companion object {
    const val LOGGER_NAME = "com.atlassian.meridian.catalog"
  }
}

/**
 * Resolves picker options. Flag off never touches the network. Flag on serves
 * a fresh cache hit, otherwise fetches and falls back to the last good snapshot.
 */
class ProviderCatalogRepository(
  private val configDriven: Boolean,
  private val ttlMillis: Long = ProviderCatalog.DEFAULT_TTL_MILLIS,
  private val clock: () -> Long = System::currentTimeMillis,
  val metrics: CatalogFetchMetrics = CatalogFetchMetrics(),
  private val correlationId: () -> String? = { null },
) {
  private val cache = ProviderCatalogCache(ttlMillis, clock)

  suspend fun paymentMethods(fetch: suspend () -> CatalogResponse): List<PaymentMethodOption> {
    if (!configDriven) return ProviderCatalog.hardcodedPicker()
    cache.fresh()?.let { return it }
    return try {
      val parsed = ProviderCatalog.parse(fetch())
      if (parsed.isEmpty()) {
        recover("malformed catalog response")
      } else {
        cache.store(parsed)
        metrics.recordSuccess()
        parsed
      }
    } catch (cancelled: java.util.concurrent.CancellationException) {
      throw cancelled
    } catch (error: Exception) {
      recover(error.message ?: error.javaClass.simpleName)
    }
  }

  private fun recover(detail: String): List<PaymentMethodOption> {
    val correlation = correlationId()
    metrics.recordFailure(detail, correlation)
    val cached = cache.lastKnownGood()
    if (cached != null) {
      metrics.recordFallback(correlation)
      return cached
    }
    metrics.recordBaseline(correlation)
    return ProviderCatalog.safeDefault()
  }
}
