package com.atlassian.meridian

import com.fasterxml.jackson.databind.DeserializationFeature
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets

/**
 * Meridian API client for Kotlin/JVM and Android
 * Uses HttpURLConnection for universal JVM/Android compatibility
 * Coroutines for async operations with UI dispatcher where needed
 */
class MeridianClient(
  private val baseURL: String,
  private val sessionId: String,
  private val clientConfig: MeridianClientConfig = MeridianClientConfig(),
  val providerConfigMetrics: ProviderConfigMetrics = ProviderConfigMetrics(),
  val paymentEventLog: PaymentEventLog = PaymentEventLog(),
  private val clock: () -> Long = System::currentTimeMillis,
) {
  private val mapper = jsonMapper()
  private val baseUrlNormalized = baseURL.removeSuffix("/")
  private val providerConfigCache = ProviderConfigCache(
    ttlMillis = clientConfig.providerConfigTtlMillis,
    clock = clock,
  )

  init {
    require(sessionId.isNotEmpty()) { "Session ID is required" }
    require(
      baseUrlNormalized.startsWith("http://") || baseUrlNormalized.startsWith("https://")
    ) { "Invalid URL: must start with http:// or https://" }
  }

  // MARK: - Internal Request Method

  private suspend fun <T> request(
    method: String,
    path: String,
    body: Any? = null,
    additionalHeaders: Map<String, String> = emptyMap(),
    responseType: Class<T>,
  ): T = withContext(Dispatchers.IO) {
    val fullUrl = "$baseUrlNormalized$path"
    val url = URL(fullUrl)

    val connection = url.openConnection() as HttpURLConnection
    try {
      connection.connectTimeout = 15000
      connection.readTimeout = 15000
      connection.requestMethod = method
      connection.setRequestProperty("Content-Type", "application/json")
      connection.setRequestProperty("X-Rehearsal-Session", sessionId)

      // Add additional headers (e.g., Idempotency-Key)
      additionalHeaders.forEach { (key, value) ->
        connection.setRequestProperty(key, value)
      }

      // Write body if present
      if (body != null) {
        val bodyJson = mapper.writeValueAsString(body)
        connection.doOutput = true
        connection.outputStream.use { out ->
          out.write(bodyJson.toByteArray(StandardCharsets.UTF_8))
          out.flush()
        }
      }

      // Read response
      val statusCode = connection.responseCode
      val responseStream = if (statusCode >= 400) {
        connection.errorStream
      } else {
        connection.inputStream
      }

      val responseBody = responseStream?.bufferedReader()?.use { it.readText() } ?: ""

      // Check HTTP status and handle errors
      when {
        statusCode >= 200 && statusCode < 300 -> {
          // Success
          try {
            mapper.readValue(responseBody, responseType)
          } catch (e: Exception) {
            throw MeridianError.DecodingError("Failed to parse response: ${e.message}", e)
          }
        }

        statusCode == 202 || statusCode == 400 || statusCode == 409 || statusCode == 422 || statusCode == 503 -> {
          // These are expected error statuses, parse the response
          try {
            mapper.readValue(responseBody, responseType)
          } catch (e: Exception) {
            throw MeridianError.HttpError(
              statusCode,
              responseBody.ifEmpty { "Unknown error" }
            )
          }
        }

        else -> {
          throw MeridianError.HttpError(
            statusCode,
            responseBody.ifEmpty { "Unknown error" }
          )
        }
      }
    } finally {
      connection.disconnect()
    }
  }

  // MARK: - Public API Methods

  /**
   * GET /health - Check service health
   */
  suspend fun getHealth(): HealthResponse =
    request("GET", "/health", responseType = HealthResponse::class.java)

  /**
   * GET /catalog - Fetch recipients and providers
   */
  suspend fun getCatalog(): CatalogResponse =
    request("GET", "/catalog", responseType = CatalogResponse::class.java)

  /**
   * Payment methods for the picker.
   * With [MeridianClientConfig.configDrivenProviders] off, returns the hardcoded
   * Adyen card and Worldpay bank list and does not fetch configuration.
   * With the flag on, loads options from GET /catalog, serves a fresh in-memory
   * cache, and on timeout or failure returns the last-known-good list or that
   * same two-provider baseline. The selected provider is never swapped for a
   * different one because a fetch timed out.
   */
  suspend fun paymentMethodOptions(): List<PaymentMethodOption> {
    if (!clientConfig.configDrivenProviders) {
      return ProviderCatalog.baseline()
    }
    providerConfigCache.fresh()?.let { return it }
    val fetched = try {
      fetchProviderOptions()
    } catch (e: CancellationException) {
      throw e
    } catch (e: Exception) {
      CatalogFetch(null, null, e.message ?: "catalog fetch failed")
    }
    val options = fetched.options
    if (options != null) {
      providerConfigCache.store(options)
      providerConfigMetrics.recordFetchSuccess()
      return options
    }
    val failure = ProviderConfigFailure(
      correlationId = fetched.correlationId,
      sessionId = sessionId,
      reason = fetched.reason ?: "catalog fetch failed",
    )
    providerConfigMetrics.recordFetchFailure(failure)
    val known = providerConfigCache.lastKnown()
    if (known != null) {
      providerConfigMetrics.recordFallbackToCache(failure)
      return known
    }
    return ProviderCatalog.baseline()
  }

  private data class CatalogFetch(
    val options: List<PaymentMethodOption>?,
    val correlationId: String?,
    val reason: String?,
  )

  private suspend fun fetchProviderOptions(): CatalogFetch = withContext(Dispatchers.IO) {
    if (!ProviderCatalog.configTransportAllowed(baseUrlNormalized)) {
      return@withContext CatalogFetch(
        options = null,
        correlationId = null,
        reason = "Provider configuration requires HTTPS",
      )
    }
    val connection = try {
      URL("$baseUrlNormalized/catalog").openConnection() as HttpURLConnection
    } catch (e: CancellationException) {
      throw e
    } catch (e: Exception) {
      return@withContext CatalogFetch(null, null, e.message ?: "catalog fetch failed")
    }
    try {
      connection.instanceFollowRedirects = false
      connection.connectTimeout = clientConfig.providerConfigTimeoutMillis
      connection.readTimeout = clientConfig.providerConfigTimeoutMillis
      connection.requestMethod = "GET"
      connection.setRequestProperty("Content-Type", "application/json")
      connection.setRequestProperty("X-Rehearsal-Session", sessionId)
      val statusCode = connection.responseCode
      val responseStream = if (statusCode >= 400) connection.errorStream else connection.inputStream
      val responseBody = responseStream?.bufferedReader()?.use { it.readText() } ?: ""
      val headers = connection.headerFields
        ?.mapNotNull { (key, value) -> if (key == null) null else key to value.toList() }
        ?.toMap()
        ?: emptyMap()
      val correlationId = ProviderCatalog.correlationId(headers, responseBody, mapper)
      if (statusCode !in 200..299) {
        return@withContext CatalogFetch(null, correlationId, "HTTP $statusCode")
      }
      val catalog = try {
        mapper.readValue(responseBody, CatalogResponse::class.java)
      } catch (e: Exception) {
        return@withContext CatalogFetch(null, correlationId, "Malformed catalog")
      }
      val options = ProviderCatalog.optionsFromCatalog(catalog)
      if (options.isEmpty()) {
        return@withContext CatalogFetch(null, correlationId, "Catalog did not include a live provider")
      }
      CatalogFetch(options, correlationId, null)
    } catch (e: CancellationException) {
      throw e
    } catch (e: Exception) {
      CatalogFetch(null, null, e.message ?: "catalog fetch failed")
    } finally {
      connection.disconnect()
    }
  }

  /**
   * GET /state - Fetch current bank state
   */
  suspend fun getState(): BankState =
    request("GET", "/state", responseType = BankState::class.java)

  /**
   * POST /payments - Submit a payment
   * @param recipientId Recipient ID
   * @param amountMinor Amount in GBP pence (integer)
   * @param method Payment method (card or bank)
   * @param note Optional note (max 200 chars)
   * @param scenario Simulation scenario
   * @param idempotencyKey Unique key for idempotency
   */
  suspend fun submitPayment(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = Scenario.success,
    idempotencyKey: String,
  ): PaymentResponse {
    val selection = ProviderCatalog.baseline().first { ProviderCatalog.wireMethod(it.id) == method }
    return postPayment(recipientId, amountMinor, selection, method, note, scenario, idempotencyKey)
  }

  /**
   * Submit a payment using a catalog method id (`adyen_card` or `worldpay_bank`).
   * The Idempotency-Key header and the wire `method` (`card` or `bank`) are unchanged.
   * An unknown id is rejected locally and is not sent to another provider.
   */
  suspend fun submitPayment(
    recipientId: String,
    amountMinor: Int,
    methodId: String,
    note: String = "",
    scenario: Scenario = Scenario.success,
    idempotencyKey: String,
  ): PaymentResponse {
    val resolved = ProviderCatalog.resolve(methodId)
      ?: throw MeridianError.ValidationError("Unknown payment method")
    val selection = providerConfigCache.lastKnown()
      ?.firstOrNull { it.id == resolved.option.id }
      ?: resolved.option
    return postPayment(
      recipientId,
      amountMinor,
      selection,
      resolved.method,
      note,
      scenario,
      idempotencyKey,
    )
  }

  private suspend fun postPayment(
    recipientId: String,
    amountMinor: Int,
    selection: PaymentMethodOption,
    method: PaymentMethod,
    note: String,
    scenario: Scenario,
    idempotencyKey: String,
  ): PaymentResponse {
    val payload = PaymentRequest(
      recipientId = recipientId,
      amountMinor = amountMinor,
      method = method.name,
      note = note,
      scenario = scenario.name,
    )
    try {
      val response = request(
        "POST",
        "/payments",
        payload,
        mapOf("Idempotency-Key" to idempotencyKey),
        PaymentResponse::class.java,
      )
      paymentEventLog.record(
        PaymentTransactionEvent(
          methodId = selection.id,
          providerName = selection.providerName,
          wireMethod = method.name,
          idempotencyKey = idempotencyKey,
          transactionId = response.transaction?.id ?: response.paymentId,
          code = response.code,
        )
      )
      return response
    } catch (e: Exception) {
      paymentEventLog.record(
        PaymentTransactionEvent(
          methodId = selection.id,
          providerName = selection.providerName,
          wireMethod = method.name,
          idempotencyKey = idempotencyKey,
          transactionId = null,
          code = "UNKNOWN",
        )
      )
      throw e
    }
  }

  /**
   * PATCH /budgets - Update budget for a category
   * @param category Budget category
   * @param limitMinor Limit in GBP pence
   */
  suspend fun updateBudget(
    category: String,
    limitMinor: Int,
  ): BudgetResponse {
    val payload = BudgetRequest(category = category, limitMinor = limitMinor)
    return request(
      "PATCH",
      "/budgets",
      payload,
      responseType = BudgetResponse::class.java,
    )
  }

  /**
   * POST /reset - Reset session state
   */
  suspend fun reset(): ResetResponse =
    request("POST", "/reset", responseType = ResetResponse::class.java)

  /**
   * GET /events - Fetch audit events
   */
  suspend fun getEvents(): EventsResponse =
    request("GET", "/events", responseType = EventsResponse::class.java)

  companion object {
    /**
     * Unknown JSON fields are ignored so a catalog extension from meridian-api
     * does not fail the payment flow before the contract is reconciled.
     */
    internal fun jsonMapper(): ObjectMapper =
      ObjectMapper().registerKotlinModule().apply {
        configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false)
      }
  }
}
