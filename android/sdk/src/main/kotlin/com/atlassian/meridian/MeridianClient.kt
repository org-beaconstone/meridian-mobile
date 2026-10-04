package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
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
  private val retryPolicy: RetryPolicy = RetryPolicy(),
  private val sleeper: suspend (Long) -> Unit = { delay(it) },
) {
  private val mapper = ObjectMapper().registerKotlinModule()
  private val baseUrlNormalized = baseURL.removeSuffix("/")
  private val healthSnapshots = MutableStateFlow(SessionHealthSnapshot())
  @Volatile private var healthJob: Job? = null

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
      if (retryPolicy.retries(statusCode)) {
        throw MeridianError.HttpError(statusCode, responseBody.ifEmpty { "Gateway error" })
      }

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
    } catch (error: MeridianError) {
      throw error
    } catch (error: IOException) {
      throw MeridianError.NetworkError(error.message ?: "Connection failed", error)
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
   * GET /session/health — corridor and rail status for this rehearsal session.
   * Full path is `{baseURL}/session/health`, which is `/api/v1/session/health` for the shared API.
   */
  suspend fun getSessionHealth(): SessionHealth =
    request("GET", "/session/health", responseType = SessionHealth::class.java)

  fun sessionHealth(): StateFlow<SessionHealthSnapshot> = healthSnapshots

  /**
   * Polls /session/health until [stopSessionHealthPolling] or the scope is cancelled.
   * A missing endpoint is recorded as unreachable and is not treated as a corridor outage.
   */
  fun startSessionHealthPolling(scope: CoroutineScope, intervalMillis: Long = 5_000): Job {
    healthJob?.cancel()
    val job = scope.launch {
      while (isActive) {
        healthSnapshots.value = loadSessionHealth()
        delay(intervalMillis)
      }
    }
    healthJob = job
    return job
  }

  fun stopSessionHealthPolling() {
    healthJob?.cancel()
    healthJob = null
  }

  suspend fun loadSessionHealth(): SessionHealthSnapshot {
    return try {
      SessionHealthSnapshot(health = getSessionHealth(), reachable = true, detail = null)
    } catch (error: CancellationException) {
      throw error
    } catch (error: MeridianError.HttpError) {
      val detail = if (error.statusCode == 404) {
        "Session health is not available"
      } else {
        error.message
      }
      SessionHealthSnapshot(health = null, reachable = false, detail = detail)
    } catch (error: Exception) {
      SessionHealthSnapshot(health = null, reachable = false, detail = error.message)
    }
  }

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
    val headers = mapOf("Idempotency-Key" to idempotencyKey)
    var lastStatus = 0
    var lastMessage = ""
    var attempt = 1
    while (attempt <= retryPolicy.maxAttempts) {
      try {
        return request(
          "POST",
          "/payments",
          payload,
          headers,
          PaymentResponse::class.java,
        )
      } catch (error: MeridianError.HttpError) {
        if (!retryPolicy.retries(error.statusCode)) throw error
        lastStatus = error.statusCode
        lastMessage = error.message ?: ""
        if (attempt == retryPolicy.maxAttempts) break
        sleeper(retryPolicy.delayMillis(beforeAttempt = attempt + 1))
        attempt += 1
      }
    }
    throw MeridianError.RetriesExhausted(
      statusCode = lastStatus,
      attempts = retryPolicy.maxAttempts,
      msg = "Gateway HTTP $lastStatus after ${retryPolicy.maxAttempts} attempts. $lastMessage".trim(),
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
