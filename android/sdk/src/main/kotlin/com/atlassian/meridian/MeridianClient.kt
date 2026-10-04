package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

/**
 * Meridian API client for Kotlin/JVM and Android
 * Uses HttpURLConnection for universal JVM/Android compatibility
 * Coroutines for async operations with UI dispatcher where needed
 */
class MeridianClient(
  private val baseURL: String,
  private val sessionId: String,
  upstreamTraceparent: String? = null,
  upstreamTracestate: String? = null,
  clock: () -> Long = { System.currentTimeMillis() },
) {
  private val mapper = ObjectMapper().registerKotlinModule()
  private val baseUrlNormalized = baseURL.removeSuffix("/")
  val telemetry = TelemetryCenter(
    upstreamTraceparent = upstreamTraceparent,
    upstreamTracestate = upstreamTracestate,
    vendor = "sdk-android",
    language = "kotlin",
    sessionId = sessionId,
    now = clock,
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
    query: Map<String, String> = emptyMap(),
    parent: OpenSpan? = null,
    responseType: Class<T>,
  ): T = withContext(Dispatchers.IO) {
    val route = path.substringBefore('?').let { if (it.startsWith("/")) it else "/$it" }
    val span = telemetry.startHttpSpan(method, route, parent)
    val fullUrl = buildUrl(path, query)
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
      connection.setRequestProperty("traceparent", span.traceparent)
      span.tracestate?.let { connection.setRequestProperty("tracestate", it) }

      if (body != null) {
        val bodyJson = mapper.writeValueAsString(body)
        connection.doOutput = true
        connection.outputStream.use { out ->
          out.write(bodyJson.toByteArray(StandardCharsets.UTF_8))
          out.flush()
        }
      }

      val statusCode = connection.responseCode
      telemetry.setAttribute(span, "http.response.status_code", statusCode.toString())
      val responseStream = if (statusCode >= 400) {
        connection.errorStream
      } else {
        connection.inputStream
      }

      val responseBody = responseStream?.bufferedReader()?.use { it.readText() } ?: ""
      val allowed = (statusCode in 200..299) || statusCode == 202 || statusCode == 400 ||
        statusCode == 409 || statusCode == 422 || statusCode == 503

      if (!allowed) {
        val errorMsg = TelemetrySanitizer.sanitize(responseBody.ifEmpty { "Unknown error" })
        telemetry.noteError(span, errorMsg)
        telemetry.endSpan(span, "error")
        throw MeridianError.HttpError(statusCode, errorMsg)
      }

      val parsed = try {
        mapper.readValue(responseBody, responseType)
      } catch (e: Exception) {
        val clean = TelemetrySanitizer.sanitize(e.message ?: "Failed to parse response")
        telemetry.noteError(span, clean)
        telemetry.endSpan(span, "error")
        if (statusCode in 200..299) {
          throw MeridianError.DecodingError("Failed to parse response: $clean", e)
        }
        throw MeridianError.HttpError(statusCode, responseBody.ifEmpty { "Unknown error" }.let(TelemetrySanitizer::sanitize))
      }

      if (statusCode >= 400) {
        telemetry.noteError(span, TelemetrySanitizer.sanitize(responseBody.ifEmpty { "HTTP $statusCode" }))
        telemetry.endSpan(span, "error")
      } else {
        telemetry.endSpan(span, "ok")
      }
      parsed
    } catch (error: CancellationException) {
      telemetry.endSpan(span, "cancelled")
      throw error
    } catch (error: MeridianError) {
      throw error
    } catch (error: Exception) {
      val clean = TelemetrySanitizer.sanitize(error.message ?: "network error")
      telemetry.noteError(span, clean)
      telemetry.endSpan(span, "error")
      throw MeridianError.NetworkError(clean, error)
    } finally {
      connection.disconnect()
    }
  }

  private fun buildUrl(path: String, query: Map<String, String>): String {
    val root = "$baseUrlNormalized$path"
    if (query.isEmpty()) return root
    val encoded = query.entries.joinToString("&") { (key, value) ->
      "${URLEncoder.encode(key, StandardCharsets.UTF_8)}=${URLEncoder.encode(value, StandardCharsets.UTF_8)}"
    }
    return "$root?$encoded"
  }

  // MARK: - Public API Methods

  /**
   * GET /health - Check service health
   */
  suspend fun getHealth(): HealthResponse =
    request("GET", "/health", responseType = HealthResponse::class.java)

  /**
   * GET /session/health - Session-scoped health used by client traces
   */
  suspend fun getSessionHealth(): SessionHealthResponse =
    request("GET", "/session/health", responseType = SessionHealthResponse::class.java)

  /**
   * GET /catalog - Fetch recipients and providers
   */
  suspend fun getCatalog(): CatalogResponse =
    request("GET", "/catalog", responseType = CatalogResponse::class.java)

  /**
   * GET /fx/quote - GBP pence quote. Quote currency stays GBP.
   */
  suspend fun getFxQuote(amountMinor: Int): FxQuoteResponse {
    if (amountMinor !in 1..1_000_000) {
      throw MeridianError.InvalidAmount("Amount must be 1..1000000 pence")
    }
    return request(
      "GET",
      "/fx/quote",
      query = linkedMapOf(
        "base" to "GBP",
        "quote" to "GBP",
        "amountMinor" to amountMinor.toString(),
      ),
      responseType = FxQuoteResponse::class.java,
    )
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
    val span = telemetry.startSpan("payment.submit")
    telemetry.setAttribute(span, "meridian.idempotency_key", idempotencyKey)
    telemetry.setAttribute(span, "payment.method", method.name)
    val payload = PaymentRequest(
      recipientId = recipientId,
      amountMinor = amountMinor,
      method = method.name,
      note = note,
      scenario = scenario.name,
    )

    try {
      val result = request(
        "POST",
        "/payments",
        payload,
        mapOf("Idempotency-Key" to idempotencyKey),
        parent = span,
        responseType = PaymentResponse::class.java,
      )
      val success = result.ok || result.code == "PAYMENT_PENDING"
      if (!success) {
        telemetry.noteError(span, result.error ?: result.code ?: "payment failed")
      }
      telemetry.endSpan(span, if (success) "ok" else "error")
      return result
    } catch (error: CancellationException) {
      telemetry.endSpan(span, "cancelled")
      throw error
    } catch (error: Exception) {
      telemetry.noteError(span, error.message ?: "payment failed")
      telemetry.endSpan(span, "error")
      throw error
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

  /** Local rehearsal timer for the biometric prompt SLO. This is not a device biometric. */
  fun measureBiometricPrompt(): BiometricPromptResult = telemetry.measureBiometricPrompt()

  fun recordBiometricPrompt(durationMs: Long): BiometricPromptResult = telemetry.recordBiometricPrompt(durationMs)

  fun recordSca(dropped: Boolean, detail: String = "") = telemetry.recordSca(dropped, detail)

  fun addBreadcrumb(message: String) = telemetry.addBreadcrumb(message)

  fun telemetrySnapshot(): TelemetrySnapshot = telemetry.snapshot()
}
