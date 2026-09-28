package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import kotlin.coroutines.coroutineContext

/**
 * Meridian API client for Kotlin/JVM and Android.
 * Uses HttpURLConnection for universal JVM/Android compatibility.
 */
class MeridianClient(
  private val baseURL: String,
  private val sessionId: String,
  val telemetry: TelemetryLog = TelemetryLog(),
) {
  private val mapper = ObjectMapper().registerKotlinModule()
  private val baseUrlNormalized = baseURL.removeSuffix("/")

  init {
    require(sessionId.isNotEmpty()) { "Session ID is required" }
    require(
      baseUrlNormalized.startsWith("http://") || baseUrlNormalized.startsWith("https://"),
    ) { "Invalid URL: must start with http:// or https://" }
  }

  private data class RawHTTP(
    val statusCode: Int,
    val body: String,
    val trace: TraceContext?,
  )

  private suspend fun perform(
    method: String,
    path: String,
    body: Any? = null,
    additionalHeaders: Map<String, String> = emptyMap(),
    trace: TraceContext? = null,
    failureStage: String,
  ): RawHTTP = withContext(Dispatchers.IO) {
    val activeTrace = trace ?: if (shouldInjectTraceparent(path)) TraceContext.root() else null
    val fullUrl = "$baseUrlNormalized$path"
    val connection = URL(fullUrl).openConnection() as HttpURLConnection
    try {
      connection.connectTimeout = 15000
      connection.readTimeout = 15000
      connection.requestMethod = method
      connection.setRequestProperty("Content-Type", "application/json")
      connection.setRequestProperty("X-Rehearsal-Session", sessionId)
      additionalHeaders.forEach { (key, value) ->
        connection.setRequestProperty(key, value)
      }
      activeTrace?.let { connection.setRequestProperty("traceparent", it.traceparent) }

      if (body != null) {
        val bodyJson = mapper.writeValueAsString(body)
        connection.doOutput = true
        connection.outputStream.use { out ->
          out.write(bodyJson.toByteArray(StandardCharsets.UTF_8))
          out.flush()
        }
      }

      val statusCode = connection.responseCode
      val responseStream = if (statusCode >= 400) connection.errorStream else connection.inputStream
      val responseBody = responseStream?.bufferedReader()?.use { it.readText() } ?: ""
      RawHTTP(statusCode, responseBody, activeTrace)
    } catch (error: CancellationException) {
      throw error
    } catch (error: MeridianError) {
      throw error
    } catch (error: Exception) {
      telemetry.recordError("NETWORK_ERROR", failureStage)
      throw MeridianError.NetworkError(TelemetrySanitizer.redact(error.message ?: "network failure"), error)
    } finally {
      connection.disconnect()
    }
  }

  private fun <T> decode(statusCode: Int, body: String, responseType: Class<T>, stage: String): T {
    when {
      statusCode in 200..299 -> {
        try {
          return mapper.readValue(body, responseType)
        } catch (error: Exception) {
          telemetry.recordError("DECODING_ERROR", stage)
          throw MeridianError.DecodingError(
            TelemetrySanitizer.redact("Failed to parse response: ${error.message}"),
            error,
          )
        }
      }

      statusCode == 202 || statusCode == 400 || statusCode == 409 || statusCode == 422 || statusCode == 503 -> {
        try {
          return mapper.readValue(body, responseType)
        } catch (error: Exception) {
          telemetry.recordError("HTTP_$statusCode", stage)
          throw MeridianError.HttpError(statusCode, TelemetrySanitizer.redact(body.ifEmpty { "Unknown error" }))
        }
      }

      else -> {
        telemetry.recordError("HTTP_$statusCode", stage)
        throw MeridianError.HttpError(statusCode, TelemetrySanitizer.redact(body.ifEmpty { "Unknown error" }))
      }
    }
  }

  private suspend fun <T> request(
    method: String,
    path: String,
    body: Any? = null,
    additionalHeaders: Map<String, String> = emptyMap(),
    responseType: Class<T>,
    failureStage: String = "network",
  ): T {
    val raw = perform(method, path, body, additionalHeaders, failureStage = failureStage)
    return decode(raw.statusCode, raw.body, responseType, failureStage)
  }

  suspend fun getHealth(): HealthResponse =
    request("GET", "/health", responseType = HealthResponse::class.java)

  suspend fun getCatalog(): CatalogResponse {
    val raw = perform("GET", "/catalog", failureStage = "network")
    if (raw.statusCode !in 200..299) {
      telemetry.recordError("HTTP_${raw.statusCode}", "network")
      throw MeridianError.HttpError(raw.statusCode, TelemetrySanitizer.redact(raw.body.ifEmpty { "Unknown error" }))
    }
    val started = System.nanoTime()
    val child = raw.trace?.child() ?: TraceContext.root()
    return try {
      val decoded = mapper.readValue(raw.body, CatalogResponse::class.java)
      telemetry.recordSpan(
        name = "catalog.parse",
        context = child,
        parentSpanId = raw.trace?.spanId,
        durationMillis = elapsedMillis(started),
        status = "ok",
        attributes = mapOf(
          "http.route" to "/api/v1/catalog",
          "recipient.count" to decoded.recipients.size.toString(),
          "provider.count" to decoded.providers.size.toString(),
        ),
      )
      decoded
    } catch (error: Exception) {
      telemetry.recordSpan(
        name = "catalog.parse",
        context = child,
        parentSpanId = raw.trace?.spanId,
        durationMillis = elapsedMillis(started),
        status = "error",
        attributes = mapOf("http.route" to "/api/v1/catalog"),
      )
      telemetry.recordError(
        "DECODING_ERROR",
        "catalog_parse",
        mapOf("error.message" to (error.message ?: "decode failed")),
      )
      throw MeridianError.DecodingError(TelemetrySanitizer.redact("Failed to parse response: ${error.message}"), error)
    }
  }

  suspend fun getState(): BankState =
    request("GET", "/state", responseType = BankState::class.java)

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
    val trace = TraceContext.root()
    val started = System.nanoTime()
    val provider = if (method == PaymentMethod.card) "adyen" else "worldpay"
    var closed = false
    fun close(status: String, statusCode: Int?, outcome: String?, message: String?) {
      if (closed) return
      closed = true
      val attributes = linkedMapOf(
        "http.route" to "/api/v1/payments",
        "http.method" to "POST",
        "payment.method" to method.name,
        "payment.provider" to provider,
      )
      statusCode?.let { attributes["http.status_code"] = it.toString() }
      outcome?.let { attributes["outcome"] = it }
      message?.let { attributes["error.message"] = it }
      telemetry.recordSpan(
        "payment.gateway",
        trace,
        null,
        elapsedMillis(started),
        status,
        attributes,
      )
    }

    val raw = try {
      perform(
        "POST",
        "/payments",
        payload,
        mapOf("Idempotency-Key" to idempotencyKey),
        trace,
        "gateway_roundtrip",
      )
    } catch (error: Exception) {
      close("error", null, "network", null)
      throw error
    }

    val decoded = try {
      decode(raw.statusCode, raw.body, PaymentResponse::class.java, "gateway_roundtrip")
    } catch (error: Exception) {
      close("error", raw.statusCode, "error", null)
      throw error
    }

    val outcome = if (decoded.ok) "ok" else decoded.code ?: "error"
    close(if (decoded.ok) "ok" else "error", raw.statusCode, outcome, decoded.error)
    if (!decoded.ok) {
      val code = decoded.code ?: "GATEWAY_ERROR"
      val attributes = linkedMapOf(
        "http.route" to "/api/v1/payments",
        "http.status_code" to raw.statusCode.toString(),
        "payment.method" to method.name,
        "payment.provider" to provider,
        "outcome" to outcome,
      )
      decoded.error?.let { attributes["error.message"] = it }
      if (code.uppercase().contains("SCA")) {
        telemetry.recordEvent("sca.fallback", code, "sca_challenge", attributes)
      } else {
        telemetry.recordError(code, "gateway_roundtrip", attributes)
      }
    }
    return decoded
  }

  suspend fun updateBudget(
    category: String,
    limitMinor: Int,
  ): BudgetResponse {
    val payload = BudgetRequest(category = category, limitMinor = limitMinor)
    return request("PATCH", "/budgets", payload, responseType = BudgetResponse::class.java)
  }

  suspend fun reset(): ResetResponse =
    request("POST", "/reset", responseType = ResetResponse::class.java)

  suspend fun getEvents(): EventsResponse =
    request("GET", "/events", responseType = EventsResponse::class.java)

  /**
   * Local rehearsal biometric resolution. No device authenticator and no
   * provider call. A fallback does not switch the payment provider.
   */
  fun resolveLocalBiometricPrompt(
    method: PaymentMethod,
    accepted: Boolean = true,
    available: Boolean = true,
  ): BiometricResolution {
    val started = System.nanoTime()
    val trace = TraceContext.root()
    val provider = if (method == PaymentMethod.card) "adyen" else "worldpay"
    val attributes = mapOf(
      "payment.method" to method.name,
      "payment.provider" to provider,
    )
    val duration = elapsedMillis(started)
    if (!available) {
      telemetry.recordSpan(
        "biometric.prompt",
        trace,
        null,
        duration,
        "fallback",
        attributes + mapOf("outcome" to "fallback"),
      )
      telemetry.recordEvent("sca.fallback", "SCA_CHALLENGE_FALLBACK", "biometric_prompt", attributes)
      return BiometricResolution(accepted = false, fallback = true, durationMillis = duration)
    }
    if (!accepted) {
      telemetry.recordSpan(
        "biometric.prompt",
        trace,
        null,
        duration,
        "error",
        attributes + mapOf("outcome" to "declined"),
      )
      telemetry.recordError("BIOMETRIC_DECLINED", "biometric_prompt", attributes)
      return BiometricResolution(accepted = false, fallback = false, durationMillis = duration)
    }
    telemetry.recordSpan(
      "biometric.prompt",
      trace,
      null,
      duration,
      "ok",
      attributes + mapOf("outcome" to "accepted"),
    )
    return BiometricResolution(accepted = true, fallback = false, durationMillis = duration)
  }

  /**
   * GET /session/health. Transport failures become an unreachable report so
   * the corridor probe cannot abort a payment retry.
   */
  suspend fun checkSessionHealth(): SessionHealthReport {
    val started = System.nanoTime()
    val trace = TraceContext.root()
    return try {
      val raw = perform("GET", "/session/health", trace = trace, failureStage = "session_health")
      val report = SessionHealthParser.parse(raw.statusCode, raw.body)
      val duration = elapsedMillis(started)
      telemetry.recordSpan(
        "session.health",
        trace,
        null,
        duration,
        if (report.connectionState == "healthy") "ok" else "error",
        mapOf(
          "http.route" to "/api/v1/session/health",
          "http.method" to "GET",
          "http.status_code" to raw.statusCode.toString(),
          "connection.current" to report.connectionState,
        ),
      )
      telemetry.observeSessionHealth(report, duration)
      report
    } catch (error: CancellationException) {
      throw error
    } catch (_: Exception) {
      val report = SessionHealthReport("unreachable", null, emptyList())
      val duration = elapsedMillis(started)
      telemetry.recordSpan(
        "session.health",
        trace,
        null,
        duration,
        "error",
        mapOf(
          "http.route" to "/api/v1/session/health",
          "http.method" to "GET",
          "connection.current" to "unreachable",
        ),
      )
      telemetry.observeSessionHealth(report, duration)
      report
    }
  }

  suspend fun runSessionHealthChecks(intervalMillis: Long = 15_000) {
    val interval = intervalMillis.coerceAtLeast(1_000)
    while (coroutineContext.isActive) {
      checkSessionHealth()
      delay(interval)
    }
  }

  private fun elapsedMillis(startedNanos: Long): Long =
    ((System.nanoTime() - startedNanos) / 1_000_000).coerceAtLeast(0)
}
