package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException
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
  private val connectTimeoutMs: Int = 15000,
  private val readTimeoutMs: Int = 15000,
) {
  /** Extra attempts after an uncertain transport failure. Session and idempotency key stay the same. */
  var maxTransportRetries: Int = 2
  private val mapper = ObjectMapper().registerKotlinModule()
  private val baseUrlNormalized = baseURL.removeSuffix("/")

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
      connection.connectTimeout = connectTimeoutMs
      connection.readTimeout = readTimeoutMs
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
      if (statusCode < 0) {
        throw MeridianError.NetworkError("Connection closed before a response")
      }
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
    } catch (e: MeridianError) {
      throw e
    } catch (e: IOException) {
      throw MeridianError.NetworkError(e.message ?: "Network error", e)
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
    val provider = providerFor(method)
    var attempt = 0
    while (true) {
      refuseProviderSwitch(provider, providerFor(method))
      try {
        return request(
          "POST",
          "/payments",
          payload,
          mapOf("Idempotency-Key" to idempotencyKey),
          PaymentResponse::class.java,
        )
      } catch (e: MeridianError.NetworkError) {
        if (attempt >= maxTransportRetries) throw e
        attempt += 1
      }
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
}
