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
  val idempotency: IdempotencyKeyManager = IdempotencyKeyManager(),
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

  private suspend fun <T> request(
    method: String,
    path: String,
    body: Any? = null,
    additionalHeaders: Map<String, String> = emptyMap(),
    responseType: Class<T>,
  ): T = withContext(Dispatchers.IO) {
    if (method.equals("POST", ignoreCase = true) && path == PAYMENTS_PATH) {
      val idempotencyKey = additionalHeaders[IdempotencyKeyManager.HEADER]
      if (idempotencyKey.isNullOrBlank()) {
        throw MeridianError.ValidationError("Idempotency-Key header is required for payment requests")
      }
    }
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
   * GET /state - Fetch current bank state
   */
  suspend fun getState(): BankState =
    request("GET", "/state", responseType = BankState::class.java)

  /**
   * Start a payment attempt and persist its UUID v4 idempotency key.
   * Review screens call this before the first network request.
   */
  fun preparePayment(
    transactionId: String,
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = Scenario.success,
  ): String = idempotency.begin(
    transactionId,
    attempt(recipientId, amountMinor, method, note, scenario).fingerprint(),
  )

  /**
   * POST /payments - Submit a payment.
   * Pass [transactionId] to generate and retain a UUID v4 key for the attempt.
   * An explicit [idempotencyKey] is still sent as the header for callers that already hold one.
   */
  suspend fun submitPayment(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = Scenario.success,
    idempotencyKey: String? = null,
    transactionId: String? = null,
  ): PaymentResponse = postPayment(
    recipientId = recipientId,
    amountMinor = amountMinor,
    method = method,
    note = note,
    scenario = scenario,
    idempotencyKey = idempotencyKey,
    transactionId = transactionId,
    mode = KeyMode.INITIAL_OR_RETRY,
  )

  /**
   * Network retry of an in-flight payment. Reuses the stored key and never mints a replacement.
   */
  suspend fun retryPayment(
    transactionId: String,
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = Scenario.success,
  ): PaymentResponse = postPayment(
    recipientId = recipientId,
    amountMinor = amountMinor,
    method = method,
    note = note,
    scenario = scenario,
    idempotencyKey = null,
    transactionId = transactionId,
    mode = KeyMode.RETRY,
  )

  /**
   * Two-factor challenge submission for an in-flight payment.
   * Uses the same Idempotency-Key and the same payment body as the original attempt.
   */
  suspend fun submitChallenge(
    transactionId: String,
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = Scenario.success,
  ): PaymentResponse = postPayment(
    recipientId = recipientId,
    amountMinor = amountMinor,
    method = method,
    note = note,
    scenario = scenario,
    idempotencyKey = null,
    transactionId = transactionId,
    mode = KeyMode.CHALLENGE,
  )

  fun cancelTransaction(transactionId: String) {
    idempotency.cancel(transactionId)
  }

  private suspend fun postPayment(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String,
    scenario: Scenario,
    idempotencyKey: String?,
    transactionId: String?,
    mode: KeyMode,
  ): PaymentResponse {
    val fingerprint = attempt(recipientId, amountMinor, method, note, scenario).fingerprint()
    val key = resolveKey(transactionId, idempotencyKey, fingerprint, mode)
    val payload = PaymentRequest(
      recipientId = recipientId,
      amountMinor = amountMinor,
      method = method.name,
      note = note,
      scenario = scenario.name,
    )
    val response = request(
      "POST",
      PAYMENTS_PATH,
      payload,
      mapOf(IdempotencyKeyManager.HEADER to key),
      PaymentResponse::class.java,
    )
    if (transactionId != null && isTerminalSuccess(response)) {
      idempotency.settle(transactionId)
    }
    return response
  }

  private fun resolveKey(
    transactionId: String?,
    idempotencyKey: String?,
    fingerprint: String,
    mode: KeyMode,
  ): String {
    val managed = !transactionId.isNullOrBlank()
    val explicit = !idempotencyKey.isNullOrBlank()
    if (managed && explicit) {
      throw MeridianError.ValidationError(
        "Pass either a managed transaction id or an explicit idempotency key",
      )
    }
    if (!managed) {
      if (!explicit) {
        throw MeridianError.ValidationError("An idempotency key or transaction id is required")
      }
      return idempotencyKey!!
    }
    val id = transactionId!!
    return when (mode) {
      KeyMode.RETRY -> idempotency.keyForRetry(id, fingerprint)
      KeyMode.CHALLENGE -> idempotency.keyForChallenge(id, fingerprint)
      KeyMode.INITIAL_OR_RETRY -> try {
        idempotency.keyForRetry(id, fingerprint)
      } catch (missing: MeridianError.MissingIdempotencyKey) {
        idempotency.begin(id, fingerprint)
      }
    }
  }

  private fun isTerminalSuccess(response: PaymentResponse): Boolean {
    if (!response.ok) return false
    if (response.code == "PAYMENT_PENDING") return false
    if (response.transaction?.status == TransactionStatus.pending.name) return false
    return true
  }

  private fun attempt(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String,
    scenario: Scenario,
  ) = PaymentAttempt(
    recipientId = recipientId,
    amountMinor = amountMinor,
    method = method.name,
    note = note,
    scenario = scenario.name,
  )

  private enum class KeyMode { INITIAL_OR_RETRY, RETRY, CHALLENGE }

  private companion object {
    const val PAYMENTS_PATH = "/payments"
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
