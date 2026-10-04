package com.atlassian.meridian

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
  private val flagCache: FeatureFlagCache = FileFeatureFlagCache(),
) {
  private val mapper = ObjectMapper().registerKotlinModule()
  private val baseUrlNormalized = baseURL.removeSuffix("/")
  private val telemetry = mutableListOf<PaymentTelemetryEvent>()
  @Volatile private var flagEvaluation = FeatureFlagEvaluation.legacy("default")

  init {
    require(sessionId.isNotEmpty()) { "Session ID is required" }
    require(
      baseUrlNormalized.startsWith("http://") || baseUrlNormalized.startsWith("https://")
    ) { "Invalid URL: must start with http:// or https://" }
  }

  // MARK: - Internal Request Method

  private data class HttpResult(val status: Int, val body: String)

  private suspend fun exchange(
    method: String,
    path: String,
    body: Any? = null,
    additionalHeaders: Map<String, String> = emptyMap(),
  ): HttpResult = withContext(Dispatchers.IO) {
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

      val statusCode = connection.responseCode
      val responseStream = if (statusCode >= 400) {
        connection.errorStream
      } else {
        connection.inputStream
      }

      val responseBody = responseStream?.bufferedReader()?.use { it.readText() } ?: ""
      HttpResult(statusCode, responseBody)
    } finally {
      connection.disconnect()
    }
  }

  private suspend fun <T> request(
    method: String,
    path: String,
    body: Any? = null,
    additionalHeaders: Map<String, String> = emptyMap(),
    responseType: Class<T>,
  ): T {
    val result = exchange(method, path, body, additionalHeaders)
    val statusCode = result.status
    val responseBody = result.body

    // Check HTTP status and handle errors
    return when {
      statusCode in 200..299 -> {
        try {
          mapper.readValue(responseBody, responseType)
        } catch (e: Exception) {
          throw MeridianError.DecodingError("Failed to parse response: ${e.message}", e)
        }
      }

      statusCode == 202 || statusCode == 400 || statusCode == 409 || statusCode == 422 || statusCode == 503 -> {
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
  }

  // MARK: - Public API Methods

  /**
   * GET /health - Check service health
   */
  suspend fun getHealth(): HealthResponse =
    request("GET", "/health", responseType = HealthResponse::class.java)

  /**
   * GET /catalog - Fetch recipients and providers.
   * Accepts the legacy two-provider document and the dynamic methods document.
   */
  suspend fun getCatalog(): CatalogResponse {
    val result = exchange("GET", "/catalog")
    if (result.status !in 200..299) {
      throw MeridianError.HttpError(result.status, result.body.ifEmpty { "Unknown error" })
    }
    return CatalogDecoder.decode(result.body)
      ?: throw MeridianError.DecodingError("Catalog response was not a JSON object")
  }

  /**
   * GET /flags - Evaluate enable_mobile_eu_payments before payment UI is shown.
   * Network and decode failures use the room cache, then the legacy kill-switch default.
   * This method does not throw.
   */
  suspend fun evaluateEuPaymentsFlag(): FeatureFlagEvaluation {
    val cacheKey = FeatureFlags.cacheKey(sessionId)
    try {
      val result = exchange("GET", "/flags")
      if (result.status in 200..299) {
        val parsed = FeatureFlagParser.parse(result.body)
        if (parsed != null) {
          val evaluation = FeatureFlagEvaluation(
            key = FeatureFlags.mobileEuPayments,
            enabled = parsed.first,
            variant = parsed.second,
            source = "remote",
          )
          flagCache.write(cacheKey, evaluation)
          flagEvaluation = evaluation
          return evaluation
        }
      } else if (result.status == 404) {
        val evaluation = FeatureFlagEvaluation.legacy("remote")
        flagCache.write(cacheKey, evaluation)
        flagEvaluation = evaluation
        return evaluation
      }
    } catch (_: Exception) {
      // Fall through to the cached evaluation.
    }
    flagCache.read(cacheKey)?.let { cached ->
      val evaluation = cached.copy(
        variant = if (cached.enabled) cached.variant else "legacy",
        source = "cache",
      )
      flagEvaluation = evaluation
      return evaluation
    }
    val fallback = FeatureFlagEvaluation.legacy("default")
    flagEvaluation = fallback
    return fallback
  }

  fun currentFlag(): FeatureFlagEvaluation = flagEvaluation

  fun paymentTelemetry(): List<PaymentTelemetryEvent> = synchronized(telemetry) { telemetry.toList() }

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
   * @param displayCurrency GBP or EUR display control. Ledger submission stays integer minor units.
   */
  suspend fun submitPayment(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = Scenario.success,
    idempotencyKey: String,
    displayCurrency: String = "GBP",
  ): PaymentResponse {
    val payload = PaymentRequest(
      recipientId = recipientId,
      amountMinor = amountMinor,
      method = method.name,
      note = note,
      scenario = scenario.name,
    )
    val event = PaymentTelemetry.event(flagEvaluation, idempotencyKey, sessionId, displayCurrency)
    synchronized(telemetry) { telemetry.add(event) }

    return request(
      "POST",
      "/payments",
      payload,
      mapOf(
        "Idempotency-Key" to idempotencyKey,
        "X-Meridian-Flag" to PaymentTelemetry.headerValue(event),
      ),
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
}
