package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets

/**
 * Meridian API client for Kotlin/JVM and Android.
 * Uses HttpURLConnection for universal JVM/Android compatibility.
 * Outgoing calls carry a W3C traceparent header. Sensitive PAN and IBAN values are redacted from telemetry.
 */
class MeridianClient(
  private val baseURL: String,
  private val sessionId: String,
  val telemetry: TelemetryLog = TelemetryLog(),
) {
  private val mapper = ObjectMapper().registerKotlinModule()
  private val baseUrlNormalized = baseURL.removeSuffix("/")
  private val sessionTraceId = TraceIds.hex(16)
  private val sessionSpanId = TraceIds.hex(8)
  private val healthLock = Any()
  private var lastConnection: String? = null
  private var lastHealthError: String? = null
  private val corridorStates = linkedMapOf<String, String>()

  init {
    require(sessionId.isNotEmpty()) { "Session ID is required" }
    require(
      baseUrlNormalized.startsWith("http://") || baseUrlNormalized.startsWith("https://")
    ) { "Invalid URL: must start with http:// or https://" }
  }

  private data class RawResponse(
    val statusCode: Int,
    val body: String,
    val traceId: String,
    val spanId: String,
  )

  private fun beginSpan(name: String, parentSpanId: String? = sessionSpanId): OpenSpan =
    telemetry.startSpan(name, traceId = sessionTraceId, parentSpanId = parentSpanId)

  private suspend fun exchange(
    method: String,
    path: String,
    body: Any? = null,
    additionalHeaders: Map<String, String> = emptyMap(),
    spanName: String,
    recordTransportErrors: Boolean = true,
  ): RawResponse = withContext(Dispatchers.IO) {
    val span = beginSpan(spanName)
    var closed = false
    fun close(status: String, attributes: Map<String, String> = emptyMap()) {
      if (!closed) {
        span.end(status, attributes)
        closed = true
      }
    }

    val url = URL("$baseUrlNormalized$path")
    val connection = url.openConnection() as HttpURLConnection
    try {
      connection.connectTimeout = 15000
      connection.readTimeout = 15000
      connection.requestMethod = method
      connection.setRequestProperty("Content-Type", "application/json")
      connection.setRequestProperty("X-Rehearsal-Session", sessionId)
      connection.setRequestProperty("traceparent", span.traceparent())
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
      val responseStream = if (statusCode >= 400) connection.errorStream else connection.inputStream
      val responseBody = responseStream?.bufferedReader()?.use { it.readText() } ?: ""
      val spanStatus = if (statusCode in 200..299) "ok" else "error"
      close(spanStatus, mapOf("http.status" to statusCode.toString(), "http.path" to path))
      RawResponse(statusCode, responseBody, span.traceId, span.spanId)
    } catch (error: IOException) {
      close("error", mapOf("http.path" to path))
      if (recordTransportErrors) {
        telemetry.recordError(
          code = "NETWORK_ERROR",
          stage = "network",
          message = error.message ?: "Connection failed",
          traceId = span.traceId,
          spanId = span.spanId,
          attributes = mapOf("http.path" to path),
        )
      }
      throw MeridianError.NetworkError(error.message ?: "Connection failed", error)
    } finally {
      connection.disconnect()
    }
  }

  private fun <T> decode(raw: RawResponse, responseType: Class<T>, stage: String): T {
    when {
      raw.statusCode in 200..299 -> {
        try {
          return mapper.readValue(raw.body, responseType)
        } catch (error: Exception) {
          telemetry.recordError(
            code = "DECODING_ERROR",
            stage = stage,
            message = error.message ?: "Failed to parse response",
            traceId = raw.traceId,
            spanId = raw.spanId,
          )
          throw MeridianError.DecodingError("Failed to parse response: ${error.message}", error)
        }
      }

      raw.statusCode == 202 || raw.statusCode == 400 || raw.statusCode == 409 || raw.statusCode == 422 || raw.statusCode == 503 -> {
        try {
          return mapper.readValue(raw.body, responseType)
        } catch (error: Exception) {
          telemetry.recordError(
            code = "HTTP_${raw.statusCode}",
            stage = stage,
            message = raw.body.ifEmpty { "Unknown error" },
            traceId = raw.traceId,
            spanId = raw.spanId,
          )
          throw MeridianError.HttpError(raw.statusCode, raw.body.ifEmpty { "Unknown error" })
        }
      }

      else -> {
        telemetry.recordError(
          code = "HTTP_${raw.statusCode}",
          stage = stage,
          message = raw.body.ifEmpty { "Unknown error" },
          traceId = raw.traceId,
          spanId = raw.spanId,
        )
        throw MeridianError.HttpError(raw.statusCode, raw.body.ifEmpty { "Unknown error" })
      }
    }
  }

  private suspend fun <T> request(
    method: String,
    path: String,
    body: Any? = null,
    additionalHeaders: Map<String, String> = emptyMap(),
    responseType: Class<T>,
    spanName: String = "http.client",
    stage: String = "network",
  ): T {
    val raw = exchange(method, path, body, additionalHeaders, spanName)
    return decode(raw, responseType, stage)
  }

  /**
   * GET /health - Check service health
   */
  suspend fun getHealth(): HealthResponse =
    request("GET", "/health", responseType = HealthResponse::class.java)

  /**
   * GET /catalog - Fetch recipients and providers, timing dynamic catalog parsing separately from the roundtrip.
   */
  suspend fun getCatalog(): CatalogResponse {
    val raw = exchange("GET", "/catalog", spanName = "http.catalog")
    val parse = beginSpan("catalog.parse", parentSpanId = raw.spanId)
    try {
      val parsed = decode(raw, CatalogResponse::class.java, stage = "catalog_parse")
      parse.end("ok", mapOf("recipientCount" to parsed.recipients.size.toString()))
      return parsed
    } catch (error: Exception) {
      parse.end("error")
      throw error
    }
  }

  /**
   * GET /state - Fetch current bank state
   */
  suspend fun getState(): BankState =
    request("GET", "/state", responseType = BankState::class.java)

  /**
   * Local biometric prompt. No credential store and no network call.
   * An unavailable sensor records an SCA fallback and leaves the selected provider unchanged.
   */
  suspend fun resolveBiometricPrompt(sensorAvailable: Boolean = true): BiometricResolution {
    val span = beginSpan("biometric.prompt")
    val outcome = if (sensorAvailable) "authenticated" else "fallback"
    if (!sensorAvailable) {
      telemetry.recordError(
        code = "SCA_FALLBACK",
        stage = "biometric",
        message = "Local biometric sensor unavailable",
        traceId = span.traceId,
        spanId = span.spanId,
        attributes = mapOf("outcome" to outcome),
      )
    }
    span.end(if (sensorAvailable) "ok" else "error", mapOf("outcome" to outcome))
    return BiometricResolution(outcome, if (sensorAvailable) null else "SCA_FALLBACK")
  }

  /**
   * POST /payments - Submit a payment.
   * The gateway span covers the HTTP roundtrip. The same idempotency key is left untouched.
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
    val raw = exchange(
      "POST",
      "/payments",
      payload,
      mapOf("Idempotency-Key" to idempotencyKey),
      spanName = "payment.gateway",
    )
    val response = decode(raw, PaymentResponse::class.java, stage = "gateway")
    val safeError = response.error?.let { Sanitizer.sanitize(it) }
    val safe = if (safeError == response.error) response else response.copy(error = safeError)
    if (!safe.ok && safe.code != "PAYMENT_PENDING") {
      telemetry.recordError(
        code = safe.code ?: "GATEWAY_ERROR",
        stage = "gateway",
        message = safe.error ?: "",
        traceId = raw.traceId,
        spanId = raw.spanId,
      )
    }
    return safe
  }

  /**
   * PATCH /budgets - Update budget for a category
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

  /**
   * GET /session/health. Records connection changes and emits an event when a corridor degrades.
   * Transport failures stay in telemetry and do not switch the selected payment provider.
   */
  suspend fun checkSessionHealth(): SessionHealthSnapshot {
    val raw = try {
      exchange("GET", "/session/health", spanName = "session.health", recordTransportErrors = false)
    } catch (error: MeridianError) {
      return updateHealth(
        connection = "disconnected",
        corridors = emptyList(),
        errorCode = "NETWORK_ERROR",
        errorMessage = error.message ?: "Connection failed",
      )
    }

    if (raw.statusCode !in 200..299) {
      return updateHealth(
        connection = "disconnected",
        corridors = emptyList(),
        errorCode = "HTTP_${raw.statusCode}",
        errorMessage = raw.body,
      )
    }

    val parsed = try {
      mapper.readValue(raw.body, SessionHealthResponse::class.java)
    } catch (error: Exception) {
      return updateHealth(
        connection = "disconnected",
        corridors = emptyList(),
        errorCode = "DECODING_ERROR",
        errorMessage = error.message ?: "Failed to parse session health",
      )
    }

    val corridors = parsed.corridors.orEmpty().map { corridor ->
      CorridorStatus(
        id = CorridorIds.canonical(corridor.id, corridor.provider),
        state = CorridorIds.state(corridor.state, corridor.status),
      )
    }
    val connection = CorridorIds.connection(parsed.connection, parsed.status, corridors)
    return updateHealth(connection, corridors, errorCode = null, errorMessage = null)
  }

  fun startSessionHealthChecks(
    scope: CoroutineScope,
    intervalMillis: Long = 15_000,
    onUpdate: (SessionHealthSnapshot) -> Unit = {},
  ): Job {
    require(intervalMillis > 0) { "Health check interval must be positive" }
    return scope.launch {
      while (isActive) {
        val snapshot = checkSessionHealth()
        onUpdate(snapshot)
        delay(intervalMillis)
      }
    }
  }

  private fun updateHealth(
    connection: String,
    corridors: List<CorridorStatus>,
    errorCode: String?,
    errorMessage: String?,
  ): SessionHealthSnapshot {
    val pending = mutableListOf<TelemetryEvent>()
    synchronized(healthLock) {
      if (lastConnection != connection) {
        pending.add(
          TelemetryEvent(
            name = "connection.state",
            code = connection.uppercase(),
            stage = "health",
            message = "Connection $connection",
            traceId = sessionTraceId,
            spanId = sessionSpanId,
            attributes = mapOf(
              "previous" to (lastConnection ?: "unknown"),
              "connection" to connection,
            ),
          )
        )
        lastConnection = connection
      }
      if (errorCode != null && errorCode != lastHealthError) {
        pending.add(
          TelemetryEvent(
            name = "client.error",
            code = errorCode,
            stage = "health",
            message = errorMessage ?: "",
            traceId = sessionTraceId,
            spanId = sessionSpanId,
            attributes = mapOf("connection" to connection),
          )
        )
        lastHealthError = errorCode
      }
      if (errorCode == null) lastHealthError = null
      for (corridor in corridors) {
        val previous = corridorStates[corridor.id]
        val degraded = corridor.state == "degraded" || corridor.state == "down"
        if (degraded && previous != corridor.state) {
          pending.add(
            TelemetryEvent(
              name = "corridor.degraded",
              code = "CORRIDOR_DEGRADED",
              stage = "health",
              message = "${corridor.id} ${corridor.state}",
              traceId = sessionTraceId,
              spanId = sessionSpanId,
              attributes = mapOf(
                "corridorId" to corridor.id,
                "state" to corridor.state,
              ),
            )
          )
        }
        corridorStates[corridor.id] = corridor.state
      }
    }
    pending.forEach { telemetry.record(it) }
    return SessionHealthSnapshot(connection, corridors)
  }
}
