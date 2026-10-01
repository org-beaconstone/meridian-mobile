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
 *
 * @param snapshotStore Optional store for resumable payment intent snapshots.
 *   Pass an [InMemoryPaymentIntentStore] for tests or an EncryptedSharedPreferences-
 *   backed store for Android production use. Omit for stateless operation.
 */
class MeridianClient(
  private val baseURL: String,
  private val sessionId: String,
  private val snapshotStore: PaymentIntentStore? = null,
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
   * POST /payments - Submit a payment.
   *
   * When a [snapshotStore] is configured, this method persists a
   * [PaymentIntentSnapshot] before and after the network call so the intent
   * can be resumed if the process is interrupted.
   *
   * @param recipientId Recipient ID
   * @param amountMinor Amount in GBP pence (integer)
   * @param method Payment method (card or bank)
   * @param note Optional note (max 200 chars)
   * @param scenario Simulation scenario
   * @param idempotencyKey Unique key for idempotency (retain across retries)
   */
  suspend fun submitPayment(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = Scenario.success,
    idempotencyKey: String,
  ): PaymentResponse {
    val payloadHash = paymentPayloadHash(recipientId, amountMinor, method.name, note)

    // Persist a created snapshot before sending so a crash during the request
    // is recoverable with the original idempotency key.
    snapshotStore?.let { store ->
      if (store.load(idempotencyKey) == null) {
        store.save(
          PaymentIntentSnapshot(
            paymentIntentId = idempotencyKey,
            idempotencyKey = idempotencyKey,
            businessPayloadHash = payloadHash,
            status = PaymentIntentStatus.created,
          )
        )
      }
    }

    val payload = PaymentRequest(
      recipientId = recipientId,
      amountMinor = amountMinor,
      method = method.name,
      note = note,
      scenario = scenario.name,
    )

    val response = request(
      "POST",
      "/payments",
      payload,
      mapOf("Idempotency-Key" to idempotencyKey),
      PaymentResponse::class.java,
    )

    // Update the snapshot to reflect the server's response status.
    snapshotStore?.let { store ->
      val newStatus = when {
        response.ok -> PaymentIntentStatus.completed
        response.code == "PAYMENT_PENDING" -> PaymentIntentStatus.pending
        else -> PaymentIntentStatus.declined
      }
      val returnHash = response.state?.let { bankStateHash(it.version, it.balance) }
      val serverIntentId = response.paymentId ?: response.transaction?.id ?: idempotencyKey

      val updated = store.load(idempotencyKey)?.also {
        it.paymentIntentId = serverIntentId
        it.status = newStatus
        it.returnStateHash = returnHash
        it.updatedAt = System.currentTimeMillis()
      } ?: PaymentIntentSnapshot(
        paymentIntentId = serverIntentId,
        idempotencyKey = idempotencyKey,
        businessPayloadHash = payloadHash,
        status = newStatus,
        returnStateHash = returnHash,
      )

      store.save(updated)
    }

    return response
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

  // MARK: - Resumption

  /**
   * Returns all non-terminal payment intent snapshots for the current account.
   *
   * Call this on app launch or after process recovery to detect in-flight
   * payments that should be retried with their original idempotency keys.
   */
  suspend fun resumeActiveIntents(): List<PaymentIntentSnapshot> =
    snapshotStore?.loadActive() ?: emptyList()
}
