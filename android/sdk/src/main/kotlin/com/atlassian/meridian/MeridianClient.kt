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
) {
  private val mapper = ObjectMapper().registerKotlinModule()
  private val baseUrlNormalized = baseURL.removeSuffix("/")

  init {
    require(sessionId.isNotEmpty()) { "Session ID is required" }
    require(
      baseUrlNormalized.startsWith("http://") || baseUrlNormalized.startsWith("https://")
    ) { "Invalid URL: must start with http:// or https://" }
  }

  // MARK: - Internal Request Method

  private data class RawResponse(val statusCode: Int, val body: String)

  private suspend fun rawResponse(
    method: String,
    path: String,
    body: Any? = null,
    additionalHeaders: Map<String, String> = emptyMap(),
    absoluteUrl: String? = null,
  ): RawResponse = withContext(Dispatchers.IO) {
    val fullUrl = absoluteUrl ?: "$baseUrlNormalized$path"
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
      RawResponse(statusCode, responseBody)
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
    absoluteUrl: String? = null,
    parseApplicationStatuses: Boolean = true,
  ): T {
    val raw = rawResponse(method, path, body, additionalHeaders, absoluteUrl)
    val statusCode = raw.statusCode
    val responseBody = raw.body
    val applicationStatus = parseApplicationStatuses &&
      (statusCode == 202 || statusCode == 400 || statusCode == 409 || statusCode == 422 || statusCode == 503)

    // Check HTTP status and handle errors
    when {
      statusCode >= 200 && statusCode < 300 -> {
        try {
          return mapper.readValue(responseBody, responseType)
        } catch (e: Exception) {
          throw MeridianError.DecodingError("Failed to parse response: ${e.message}", e)
        }
      }

      applicationStatus -> {
        try {
          return mapper.readValue(responseBody, responseType)
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
   * GET /catalog - Fetch recipients and providers
   */
  suspend fun getCatalog(): CatalogResponse =
    request("GET", "/catalog", responseType = CatalogResponse::class.java)

  /**
   * Absolute URL for GET /api/v2/payment-methods.
   * The rehearsal client base remains /api/v1; this sibling path does not replace it.
   */
  fun paymentMethodsUrl(accountScope: String, corridor: String, currency: String = "GBP"): String =
    buildPaymentMethodsUrl(baseUrlNormalized, accountScope, corridor, currency)

  /**
   * GET /api/v2/payment-methods. Keeps the user-selected rehearsal session.
   * A non-success HTTP status is an error. This call does not choose a payment provider.
   */
  suspend fun fetchPaymentMethods(
    accountScope: String,
    corridor: String,
    currency: String = "GBP",
  ): PaymentMethodsCatalog {
    val url = paymentMethodsUrl(accountScope, corridor, currency)
    val raw = rawResponse(method = "GET", path = "", absoluteUrl = url)
    if (raw.statusCode < 200 || raw.statusCode >= 300) {
      throw MeridianError.HttpError(raw.statusCode, raw.body.ifEmpty { "Unknown error" })
    }
    val catalog = try {
      parsePaymentMethodsCatalog(raw.body)
    } catch (error: MeridianError) {
      throw error
    } catch (error: Exception) {
      throw MeridianError.DecodingError("Failed to parse payment method catalog: ${error.message}", error)
    }
    return catalog.forRequest(accountScope, corridor, currency)
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
    val payload = PaymentRequest(
      recipientId = recipientId,
      amountMinor = amountMinor,
      method = method.name,
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
}
