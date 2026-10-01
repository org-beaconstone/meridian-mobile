package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.random.Random

/**
 * Meridian API client for Kotlin/JVM and Android
 * Uses HttpURLConnection for universal JVM/Android compatibility
 * Coroutines for async operations with UI dispatcher where needed
 */
class MeridianClient(
  private val baseURL: String,
  private val sessionId: String,
  private val telemetryConfig: TelemetryConfig = TelemetryConfig(),
) {
  private val mapper = ObjectMapper().registerKotlinModule()
  private val baseUrlNormalized = baseURL.removeSuffix("/")

  /** Cached catalog from the most recent [getCatalog] call, used for telemetry enrichment. */
  @Volatile private var cachedCatalog: CatalogResponse? = null

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
    traceContext: TraceContext = TraceContext.generate(),
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
      connection.setRequestProperty("X-Trace-ID", traceContext.traceparent)

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
   * Caches the response for telemetry enrichment of subsequent payment calls.
   */
  suspend fun getCatalog(): CatalogResponse {
    val catalog = request("GET", "/catalog", responseType = CatalogResponse::class.java)
    cachedCatalog = catalog
    return catalog
  }

  /**
   * GET /state - Fetch current bank state
   */
  suspend fun getState(): BankState =
    request("GET", "/state", responseType = BankState::class.java)

  /**
   * POST /payments - Submit a payment
   *
   * Emits a structured [AuditLogEntry] on every call via the configured [TelemetryConfig].
   * The idempotency key is hashed (SHA-256) before logging; no raw key, token, or bank
   * credential ever appears in telemetry. Failed-journey entries are subject to the
   * configured [TelemetryConfig.failedJourneySampleRate].
   *
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
    val trace = TraceContext.generate()
    val startMs = System.currentTimeMillis()
    var outcome = "error"

    try {
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
        trace,
      )

      outcome = when {
        response.ok -> "success"
        response.code == "PAYMENT_PENDING" -> "pending"
        else -> "declined"
      }

      return response
    } catch (e: Exception) {
      outcome = "error"
      throw e
    } finally {
      val latencyMs = System.currentTimeMillis() - startMs
      emitPaymentTelemetry(
        trace = trace,
        outcome = outcome,
        idempotencyKey = idempotencyKey,
        method = method,
        amountMinor = amountMinor,
        latencyMs = latencyMs,
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

  // MARK: - Private Telemetry Helpers

  private fun emitPaymentTelemetry(
    trace: TraceContext,
    outcome: String,
    idempotencyKey: String,
    method: PaymentMethod,
    amountMinor: Int,
    latencyMs: Long,
  ) {
    // Successful journeys are always logged; failed journeys are subject to sampling.
    val sampled = outcome == "success" || Random.nextDouble() < telemetryConfig.failedJourneySampleRate
    if (!sampled) return

    val catalog = cachedCatalog
    val catalogAgeDays = catalog?.let {
      try {
        ChronoUnit.DAYS.between(LocalDate.parse(it.demoDate), LocalDate.now())
      } catch (ignored: Exception) {
        null
      }
    }
    val methodCount = catalog?.providers?.sumOf { it.methods.size }

    // SCA (PSD2) applies to bank-method payments and to journeys that returned pending.
    val scaInvoked = method == PaymentMethod.bank || outcome == "pending"

    val entry = AuditLogEntry(
      traceId = trace.traceId,
      timestamp = Instant.now().toString(),
      event = "payment.completed",
      outcome = outcome,
      hashedIdempotencyKey = hashIdempotencyKey(idempotencyKey),
      catalogAgeDays = catalogAgeDays,
      methodCount = methodCount,
      scaInvoked = scaInvoked,
      latencyMs = latencyMs,
      amountMinor = amountMinor,
      paymentMethod = method.name,
    )

    telemetryConfig.onEntry(entry)
  }
}
