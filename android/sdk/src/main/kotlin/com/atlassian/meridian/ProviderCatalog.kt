package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import java.net.URL
import java.util.ArrayDeque
import java.util.concurrent.atomic.AtomicLong
import java.util.logging.Logger

/**
 * Maps the agreed GET /catalog provider registry onto selectable method options.
 * The registry is Adyen/card and Worldpay/bank. Any other provider id is ignored.
 */
object ProviderCatalog {
  const val ADYEN_CARD_ID = "adyen_card"
  const val WORLDPAY_BANK_ID = "worldpay_bank"

  private const val ADYEN_ID = "adyen"
  private const val WORLDPAY_ID = "worldpay"
  private const val ADYEN_NAME = "Adyen"
  private const val WORLDPAY_NAME = "Worldpay"

  fun baseline(): List<PaymentMethodOption> = listOf(
    PaymentMethodOption(ADYEN_CARD_ID, "Debit card", ADYEN_NAME),
    PaymentMethodOption(WORLDPAY_BANK_ID, "Bank payment", WORLDPAY_NAME),
  )

  /**
   * Derive method options from the current catalog contract:
   * `providers[].id`, `providers[].name`, `providers[].methods`.
   * An empty result means the payload did not include a live provider.
   */
  fun optionsFromCatalog(catalog: CatalogResponse): List<PaymentMethodOption> {
    val options = mutableListOf<PaymentMethodOption>()
    for (provider in catalog.providers) {
      val methods = provider.methods
      when (provider.id) {
        ADYEN_ID -> if (methods.any { it == PaymentMethod.card.name }) {
          options += PaymentMethodOption(
            ADYEN_CARD_ID,
            "Debit card",
            canonicalName(ADYEN_NAME, provider.name),
          )
        }
        WORLDPAY_ID -> if (methods.any { it == PaymentMethod.bank.name }) {
          options += PaymentMethodOption(
            WORLDPAY_BANK_ID,
            "Bank payment",
            canonicalName(WORLDPAY_NAME, provider.name),
          )
        }
      }
    }
    return options.distinctBy { it.id }
  }

  fun resolve(methodId: String): ResolvedPaymentMethod? {
    val match = baseline().firstOrNull { it.id == methodId }
    if (match != null) {
      val method = wireMethod(match.id) ?: return null
      return ResolvedPaymentMethod(match, method)
    }
    return when (methodId) {
      PaymentMethod.card.name -> ResolvedPaymentMethod(baseline()[0], PaymentMethod.card)
      PaymentMethod.bank.name -> ResolvedPaymentMethod(baseline()[1], PaymentMethod.bank)
      else -> null
    }
  }

  fun wireMethod(methodId: String): PaymentMethod? = when (methodId) {
    ADYEN_CARD_ID, PaymentMethod.card.name -> PaymentMethod.card
    WORLDPAY_BANK_ID, PaymentMethod.bank.name -> PaymentMethod.bank
    else -> null
  }

  /**
   * Shared hosted catalog calls use HTTPS. Loopback and the Android emulator
   * alias stay on HTTP for the local rehearsal only.
   */
  fun configTransportAllowed(baseUrl: String): Boolean {
    val url = try {
      URL(baseUrl)
    } catch (_: Exception) {
      return false
    }
    if (url.protocol == "https") return true
    if (url.protocol != "http") return false
    val host = url.host?.lowercase() ?: return false
    return host == "localhost" || host == "127.0.0.1" || host == "10.0.2.2" || host == "::1"
  }

  fun correlationId(headers: Map<String, List<String>>, body: String, mapper: ObjectMapper): String? {
    fun header(name: String): String? =
      headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }
        ?.value
        ?.firstOrNull { it.isNotBlank() }

    header("X-Correlation-Id")?.let { return it }
    header("X-Request-Id")?.let { return it }
    if (body.isBlank()) return null
    return try {
      val node = mapper.readTree(body)
      sequenceOf("correlationId", "requestId", "traceId")
        .mapNotNull { key -> node.get(key)?.asText() }
        .firstOrNull { it.isNotBlank() }
    } catch (_: Exception) {
      null
    }
  }

  /**
   * The catalog entry decides whether a live provider is offered. The customer-facing
   * brand stays Adyen or Worldpay, including when the payload only differs by case.
   * Any other label is not shown.
   */
  private fun canonicalName(canonical: String, catalogName: String?): String {
    val trimmed = catalogName?.trim().orEmpty()
    if (trimmed.equals(canonical, ignoreCase = true)) return canonical
    return canonical
  }
}

data class ResolvedPaymentMethod(
  val option: PaymentMethodOption,
  val method: PaymentMethod,
)

/**
 * In-memory provider configuration. Expired entries stay available as last-known-good.
 */
class ProviderConfigCache(
  private val ttlMillis: Long,
  private val clock: () -> Long = System::currentTimeMillis,
) {
  private val lock = Any()
  private var cached: List<PaymentMethodOption>? = null
  private var storedAtMillis: Long? = null

  init {
    require(ttlMillis > 0) { "Provider config TTL must be positive" }
  }

  fun fresh(): List<PaymentMethodOption>? = synchronized(lock) {
    val value = cached ?: return null
    val storedAt = storedAtMillis ?: return null
    if (clock() - storedAt < ttlMillis) value else null
  }

  fun lastKnown(): List<PaymentMethodOption>? = synchronized(lock) { cached }

  fun store(options: List<PaymentMethodOption>) {
    require(options.isNotEmpty()) { "Refusing to cache an empty provider list" }
    synchronized(lock) {
      cached = options.toList()
      storedAtMillis = clock()
    }
  }
}

data class ProviderConfigFailure(
  val correlationId: String?,
  val sessionId: String,
  val reason: String,
)

/**
 * Counters backing provider-config fetch success, failure, and fallback rates.
 * Failures keep the meridian-api correlation id when the response supplied one.
 */
class ProviderConfigMetrics {
  private val successCount = AtomicLong()
  private val failureCount = AtomicLong()
  private val fallbackCount = AtomicLong()
  private val lock = Any()
  private val failures = ArrayDeque<ProviderConfigFailure>()
  private val log = Logger.getLogger("com.atlassian.meridian.provider_config")

  val fetchSuccessCount: Long get() = successCount.get()
  val fetchFailureCount: Long get() = failureCount.get()
  val fallbackToCacheCount: Long get() = fallbackCount.get()

  fun recordFetchSuccess() {
    successCount.incrementAndGet()
    log.fine("provider_config_fetch_success")
  }

  fun recordFetchFailure(failure: ProviderConfigFailure) {
    failureCount.incrementAndGet()
    synchronized(lock) {
      failures.addLast(failure)
      while (failures.size > 20) failures.removeFirst()
    }
    log.warning(
      "provider_config_fetch_failure correlationId=${failure.correlationId ?: ""} " +
        "sessionId=${failure.sessionId} reason=${failure.reason}"
    )
  }

  fun recordFallbackToCache(failure: ProviderConfigFailure) {
    fallbackCount.incrementAndGet()
    log.warning(
      "provider_config_fallback_to_cache correlationId=${failure.correlationId ?: ""} " +
        "sessionId=${failure.sessionId}"
    )
  }

  fun recentFailures(): List<ProviderConfigFailure> = synchronized(lock) { failures.toList() }
}

data class PaymentTransactionEvent(
  val action: String = "payment.method_selected",
  val methodId: String,
  val providerName: String,
  val wireMethod: String,
  val idempotencyKey: String,
  val transactionId: String?,
  val code: String?,
)

/**
 * Provider selection recorded with the payment so it can be joined to the
 * meridian-api transaction audit by payment id and idempotency key.
 */
class PaymentEventLog {
  private val lock = Any()
  private val events = ArrayDeque<PaymentTransactionEvent>()
  private val byProvider = linkedMapOf<String, AtomicLong>()
  private val log = Logger.getLogger("com.atlassian.meridian.payment")

  fun record(event: PaymentTransactionEvent) {
    log.info(
      "payment.method_selected methodId=${event.methodId} provider=${event.providerName} " +
        "wireMethod=${event.wireMethod} idempotencyKey=${event.idempotencyKey} " +
        "transactionId=${event.transactionId ?: ""}"
    )
    synchronized(lock) {
      events.addLast(event)
      while (events.size > 50) events.removeFirst()
      byProvider.getOrPut(event.providerName) { AtomicLong() }.incrementAndGet()
    }
  }

  fun snapshot(): List<PaymentTransactionEvent> = synchronized(lock) { events.toList() }

  fun selectionCounts(): Map<String, Long> = synchronized(lock) {
    byProvider.mapValues { it.value.get() }
  }
}
