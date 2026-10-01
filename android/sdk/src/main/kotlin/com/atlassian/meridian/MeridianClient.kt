package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets

/**
 * Meridian API client for Kotlin/JVM and Android.
 * Uses HttpURLConnection for universal JVM/Android compatibility.
 * Coroutines for async operations with UI dispatcher where needed.
 */
class MeridianClient(
  private val baseURL: String,
  private val sessionId: String,
  private val telemetryConfig: TelemetryConfig = TelemetryConfig(),
) {
  private val mapper = ObjectMapper().registerKotlinModule()
  private val baseUrlNormalized = baseURL.removeSuffix("/")
  private val traceContext = TraceContext()

  // Catalog metadata captured during getCatalog() for telemetry correlation.
  @Volatile private var catalogVersion: String? = null
  @Volatile private var catalogFetchedAtMs: Long? = null
  @Volatile private var catalogMethodCount: Int? = null

  init {
    require(sessionId.isNotEmpty()) { "Session ID is required" }
    require(
      baseUrlNormalized.startsWith("http://") || baseUrlNormalized.startsWith("https://")
    ) { "Invalid URL: must start with http:// or https://" }
  }

  /** The trace ID for this client session, for correlation in error reports. */
  val traceId: String get() = traceContext.traceId

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

      // Propagate distributed trace context on every outgoing request.
      val spanId = TraceContext.newSpanId()
      connection.setRequestProperty("traceparent", traceContext.traceparent(spanId))
      connection.setRequestProperty("X-Trace-Id", traceContext.traceId)

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
   * GET /catalog - Fetch recipients and providers.
   * Catalog metadata (version, method count) is stored for telemetry correlation.
   */
  suspend fun getCatalog(): CatalogResponse {
    val response = request("GET", "/catalog", responseType = CatalogResponse::class.java)
    catalogVersion = response.demoDate
    catalogFetchedAtMs = System.currentTimeMillis()
    catalogMethodCount = response.providers.sumOf { it.methods.size }
    return response
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

    val catalogAge = catalogFetchedAtMs?.let {
      (System.currentTimeMillis() - it) / 1000.0
    }
    val startMs = System.currentTimeMillis()

    val response: PaymentResponse
    try {
      response = request(
        "POST",
        "/payments",
        payload,
        mapOf("Idempotency-Key" to idempotencyKey),
        PaymentResponse::class.java,
      )
    } catch (e: Exception) {
      val latencyMs = System.currentTimeMillis() - startMs
      emitTelemetry(PaymentOutcome.ERROR, method == PaymentMethod.card, latencyMs, catalogAge)
      emitAudit("PAYMENT_ERROR", idempotencyKey, method.name, "error", sample = true)
      throw e
    }

    val latencyMs = System.currentTimeMillis() - startMs
    val outcome = when {
      response.ok -> PaymentOutcome.SUCCESS
      response.code == "PAYMENT_PENDING" -> PaymentOutcome.PENDING
      else -> PaymentOutcome.DECLINED
    }

    emitTelemetry(outcome, method == PaymentMethod.card, latencyMs, catalogAge)

    // Successful journeys are always audited; failed journeys respect the sampling rate.
    val shouldAudit =
      outcome == PaymentOutcome.SUCCESS ||
        Math.random() < telemetryConfig.failedJourneySamplingRate
    emitAudit("PAYMENT_SUBMITTED", idempotencyKey, method.name, outcome.name.lowercase(), shouldAudit)

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

  // MARK: - Telemetry Helpers

  private fun emitTelemetry(
    outcome: PaymentOutcome,
    scaInvoked: Boolean,
    latencyMs: Long,
    catalogAge: Double?,
  ) {
    telemetryConfig.onEvent?.invoke(
      PaymentJourneyEvent(
        traceId = traceContext.traceId,
        catalogAgeSeconds = catalogAge,
        methodCount = catalogMethodCount,
        scaInvoked = scaInvoked,
        latencyMs = latencyMs,
        outcome = outcome,
        timestamp = isoNow(),
      )
    )
  }

  private fun emitAudit(
    action: String,
    idempotencyKey: String,
    paymentMethod: String,
    outcome: String,
    sample: Boolean,
  ) {
    if (!sample) return
    telemetryConfig.onAudit?.invoke(
      AuditLogEntry(
        traceId = traceContext.traceId,
        timestamp = isoNow(),
        action = action,
        hashedIdempotencyKey = sha256Hex(idempotencyKey),
        catalogVersion = catalogVersion,
        paymentMethod = paymentMethod,
        outcome = outcome,
      )
    )
  }
}
