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

  private data class RawHttp(val statusCode: Int, val body: String)

  private suspend fun <T> request(
    method: String,
    path: String,
    body: Any? = null,
    additionalHeaders: Map<String, String> = emptyMap(),
    responseType: Class<T>,
  ): T {
    val raw = exchange(method, path, body, additionalHeaders)
    return try {
      mapper.readValue(raw.body, responseType)
    } catch (e: Exception) {
      if (raw.statusCode >= 200 && raw.statusCode < 300) {
        throw MeridianError.DecodingError("Failed to parse response: ${e.message}", e)
      }
      throw MeridianError.HttpError(raw.statusCode, raw.body.ifEmpty { "Unknown error" })
    }
  }

  private suspend fun exchange(
    method: String,
    path: String,
    body: Any? = null,
    additionalHeaders: Map<String, String> = emptyMap(),
  ): RawHttp = withContext(Dispatchers.IO) {
    val fullUrl = "$baseUrlNormalized$path"
    val url = URL(fullUrl)

    val connection = url.openConnection() as HttpURLConnection
    try {
      connection.connectTimeout = 15000
      connection.readTimeout = 15000
      connection.requestMethod = method
      connection.setRequestProperty("Content-Type", "application/json")
      connection.setRequestProperty("X-Rehearsal-Session", sessionId)

      additionalHeaders.forEach { (key, value) ->
        connection.setRequestProperty(key, value)
      }

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

      if (
        statusCode >= 200 && statusCode < 300 ||
        statusCode == 202 ||
        statusCode == 400 ||
        statusCode == 409 ||
        statusCode == 422 ||
        statusCode == 503
      ) {
        RawHttp(statusCode, responseBody)
      } else {
        throw MeridianError.HttpError(statusCode, responseBody.ifEmpty { "Unknown error" })
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
   * @param idempotencyKey Unique key for idempotency. Reuse it for SCA resubmit and uncertain retries.
   * @param scaChallengeToken Set only after local biometric or passcode verification. Omitted on the first submit.
   */
  suspend fun submitPayment(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = Scenario.success,
    idempotencyKey: String,
    scaChallengeToken: String? = null,
  ): PaymentCall {
    val payload = PaymentRequest(
      recipientId = recipientId,
      amountMinor = amountMinor,
      method = method.name,
      note = note,
      scenario = scenario.name,
      scaChallengeToken = scaChallengeToken,
    )

    val raw = exchange(
      "POST",
      "/payments",
      payload,
      mapOf("Idempotency-Key" to idempotencyKey),
    )
    val decoded = try {
      mapper.readValue(raw.body, PaymentResponse::class.java)
    } catch (_: Exception) {
      null
    }
    if (decoded != null) {
      return PaymentCall(raw.statusCode, decoded, raw.body)
    }
    return when (ScaInterpreter.intercept(raw.statusCode, raw.body)) {
      is ScaIntercept.NotStepUp -> throw MeridianError.DecodingError("Payment response could not be decoded")
      else -> PaymentCall(
        raw.statusCode,
        PaymentResponse(ok = false, error = ScaCopy.FAILURE_MESSAGE, code = ScaCopy.STEP_UP_CODE),
        raw.body,
      )
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
