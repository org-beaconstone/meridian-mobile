package com.atlassian.meridian

import com.fasterxml.jackson.databind.DeserializationFeature
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
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
  configDrivenCatalog: Boolean = false,
  catalogTtlMillis: Long = ProviderCatalog.DEFAULT_TTL_MILLIS,
  clock: () -> Long = System::currentTimeMillis,
  catalogMetrics: CatalogFetchMetrics = CatalogFetchMetrics(),
) {
  val usesConfigDrivenCatalog: Boolean = configDrivenCatalog
  val catalogMetrics: CatalogFetchMetrics = catalogMetrics

  private val mapper = ObjectMapper().registerKotlinModule().apply {
    // Match Swift JSONDecoder: additive catalog fields must not fail the picker.
    disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)
  }
  private val baseUrlNormalized = baseURL.removeSuffix("/")
  private val paymentLog = java.util.logging.Logger.getLogger("com.atlassian.meridian.payment")

  @Volatile
  private var lastCorrelationId: String? = null

  private val catalogRepository = ProviderCatalogRepository(
    configDriven = configDrivenCatalog,
    ttlMillis = catalogTtlMillis,
    clock = clock,
    metrics = catalogMetrics,
    correlationId = { lastCorrelationId },
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
      lastCorrelationId = correlationIdOf(connection)
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
   * Flag off returns the hardcoded Adyen card / Worldpay bank pair and does not
   * read the catalog. Flag on parses `GET /catalog`, serves a short-lived memory
   * cache, and on failure or a malformed body returns the last known good list.
   * This does not throw for catalog failures.
   */
  suspend fun paymentMethods(): List<PaymentMethodOption> {
    if (usesConfigDrivenCatalog) lastCorrelationId = null
    return catalogRepository.paymentMethods { getCatalog() }
  }

  /**
   * GET /state - Fetch current bank state
   */
  suspend fun getState(): BankState =
    request("GET", "/state", responseType = BankState::class.java)

  /**
   * POST /payments - Submit a payment.
   * [methodId] is `card` / `bank` (hardcoded picker) or `adyen_card` / `worldpay_bank`
   * (catalog picker). The JSON method stays `card` or `bank`. The idempotency key
   * is forwarded unchanged and is not regenerated here.
   * @param recipientId Recipient ID
   * @param amountMinor Amount in GBP pence (integer)
   * @param methodId Payment method id from the picker
   * @param note Optional note (max 200 chars)
   * @param scenario Simulation scenario
   * @param idempotencyKey Unique key for idempotency
   */
  suspend fun submitPayment(
    recipientId: String,
    amountMinor: Int,
    methodId: String,
    note: String = "",
    scenario: Scenario = Scenario.success,
    idempotencyKey: String,
  ): PaymentResponse {
    val wireMethod = ProviderCatalog.wireMethod(methodId)
    paymentLog.info("payment_submit methodId=${methodId.trim()} wireMethod=$wireMethod")
    val payload = PaymentRequest(
      recipientId = recipientId,
      amountMinor = amountMinor,
      method = wireMethod,
      note = note,
      scenario = scenario.name,
    )

    return request(
      "POST",
      "/payments",
      payload,
      mapOf("Idempotency-Key" to idempotencyKey),
      PaymentResponse::class.java,
    )
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

  private fun correlationIdOf(connection: HttpURLConnection): String? {
    val names = listOf("X-Correlation-Id", "X-Request-Id", "X-Correlation-ID")
    return names.firstNotNullOfOrNull { name ->
      connection.getHeaderField(name)?.takeIf { it.isNotBlank() }
    }
  }
}
