package com.atlassian.meridian

import java.security.SecureRandom
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * In-process OpenTelemetry-compatible tracing.
 * W3C traceparent is injected on selected API calls. Spans and events stay in
 * memory: no collector export and no payment-provider network calls.
 */
data class TraceContext(
  val traceId: String,
  val spanId: String,
  val sampled: Boolean = true,
) {
  val traceparent: String
    get() = "00-$traceId-$spanId-${if (sampled) "01" else "00"}"

  fun child(): TraceContext = TraceContext(traceId, TraceIds.hex(8), sampled)

  companion object {
    fun root(): TraceContext = TraceContext(TraceIds.hex(16), TraceIds.hex(8), true)

    fun isValidTraceparent(value: String): Boolean {
      val parts = value.split("-")
      if (parts.size != 4) return false
      val (version, trace, span, flags) = parts
      if (version != "00" || flags.length != 2) return false
      if (trace.length != 32 || span.length != 16) return false
      if (trace.all { it == '0' } || span.all { it == '0' }) return false
      val hex = "0123456789abcdef"
      return listOf(trace, span, flags).all { token -> token.all { it in hex } }
    }
  }
}

private object TraceIds {
  private val random = SecureRandom()

  fun hex(byteCount: Int): String {
    val bytes = ByteArray(byteCount)
    do {
      random.nextBytes(bytes)
    } while (bytes.all { it == 0.toByte() })
    return bytes.joinToString("") { "%02x".format(it) }
  }
}

data class SpanRecord(
  val name: String,
  val traceId: String,
  val spanId: String,
  val parentSpanId: String?,
  val durationMillis: Long,
  val status: String,
  val attributes: Map<String, String>,
)

data class TelemetryEvent(
  val name: String,
  val errorCode: String,
  val failureStage: String,
  val attributes: Map<String, String>,
)

data class CorridorHealth(
  val id: String,
  val state: String,
  val provider: String?,
  val method: String?,
)

data class SessionHealthReport(
  val connectionState: String,
  val httpStatus: Int?,
  val corridors: List<CorridorHealth>,
)

data class BiometricResolution(
  val accepted: Boolean,
  val fallback: Boolean,
  val durationMillis: Long,
)

object TelemetrySanitizer {
  private val ibanCompact = Regex("(?i)(?<![A-Za-z0-9])[A-Za-z]{2}[0-9]{2}[A-Za-z0-9]{11,30}(?![A-Za-z0-9])")
  private val ibanGrouped = Regex("(?i)(?<![A-Za-z0-9])[A-Za-z]{2}[0-9]{2}(?:[ -][A-Za-z0-9]{4}){2,7}(?:[ -][A-Za-z0-9]{1,3})?(?![A-Za-z0-9])")
  private val pan = Regex("(?<![0-9])(?:[0-9][ -]?){12,18}[0-9](?![0-9])")

  fun redact(input: String): String =
    input.replace(ibanGrouped, "[REDACTED_IBAN]").replace(ibanCompact, "[REDACTED_IBAN]").replace(pan, "[REDACTED_PAN]")

  fun containsSensitive(input: String): Boolean = redact(input) != input
}

fun shouldInjectTraceparent(path: String): Boolean {
  val bare = path.substringBefore("?").let { if (it.length > 1 && it.endsWith("/")) it.dropLast(1) else it }
  return bare.endsWith("/catalog") || bare.endsWith("/payments") || bare.endsWith("/session/health")
}

internal object SessionHealthParser {
  fun parse(statusCode: Int, body: String): SessionHealthReport {
    if (statusCode == 0) {
      return SessionHealthReport("unreachable", null, emptyList())
    }
    val json = runCatching {
      com.fasterxml.jackson.databind.ObjectMapper().readTree(body)
    }.getOrNull()
    val status = json?.get("status")?.asText()?.lowercase() ?: ""
    val corridors = mutableListOf<CorridorHealth>()
    val rows = json?.get("corridors")
    if (rows != null && rows.isArray) {
      for (row in rows) {
        normalize(
          id = row.get("id")?.asText(),
          provider = row.get("provider")?.asText(),
          method = row.get("method")?.asText(),
          state = row.get("state")?.asText(),
        )?.let { corridors.add(it) }
      }
    }
    return SessionHealthReport(
      connectionState(status, statusCode, corridors),
      statusCode,
      corridors,
    )
  }

  private fun connectionState(status: String, httpStatus: Int, corridors: List<CorridorHealth>): String {
    if (httpStatus >= 500 || httpStatus == 0) return "unreachable"
    if (corridors.any { it.state == "down" }) return "unreachable"
    if (corridors.any { it.state == "degraded" }) return "degraded"
    return when (status) {
      "up", "ok", "healthy" -> if (httpStatus >= 400) "degraded" else "healthy"
      "degraded", "warn", "warning" -> "degraded"
      "down", "unavailable", "unreachable" -> "unreachable"
      else -> "degraded"
    }
  }

  private fun normalize(id: String?, provider: String?, method: String?, state: String?): CorridorHealth? {
    val normalizedState = when (state?.lowercase()) {
      "ok", "up", "healthy" -> "healthy"
      "degraded", "warn", "warning" -> "degraded"
      "down", "unavailable", "unreachable" -> "down"
      else -> return null
    }
    val providerName = provider?.lowercase()
    val methodName = method?.lowercase()
    val corridorId = id?.lowercase()
    val mapped = when {
      providerName == "adyen" && (methodName == null || methodName == "card") ->
        Triple("adyen-card", "adyen", "card")
      providerName == "worldpay" && (methodName == null || methodName == "bank") ->
        Triple("worldpay-bank", "worldpay", "bank")
      corridorId == "adyen-card" -> Triple("adyen-card", "adyen", "card")
      corridorId == "worldpay-bank" -> Triple("worldpay-bank", "worldpay", "bank")
      else -> null
    }
    if (mapped != null) {
      return CorridorHealth(mapped.first, normalizedState, mapped.second, mapped.third)
    }
    if (normalizedState == "healthy") return null
    return CorridorHealth("session", normalizedState, null, null)
  }
}

class TelemetryLog {
  private val lock = ReentrantLock()
  private val spanList = mutableListOf<SpanRecord>()
  private val eventList = mutableListOf<TelemetryEvent>()
  private var connection = "unknown"
  private val corridorStates = mutableMapOf<String, String>()

  fun spans(): List<SpanRecord> = lock.withLock { spanList.toList() }

  fun events(): List<TelemetryEvent> = lock.withLock { eventList.toList() }

  fun connectionState(): String = lock.withLock { connection }

  fun rendered(): String = lock.withLock {
    val spans = spanList.joinToString("\n") { span ->
      val attrs = span.attributes.toSortedMap().entries.joinToString(",") { "${it.key}=${it.value}" }
      "span ${span.name} ${span.status} $attrs"
    }
    val events = eventList.joinToString("\n") { event ->
      val attrs = event.attributes.toSortedMap().entries.joinToString(",") { "${it.key}=${it.value}" }
      "event ${event.name} ${event.errorCode} ${event.failureStage} $attrs"
    }
    "$spans\n$events"
  }

  internal fun recordSpan(
    name: String,
    context: TraceContext,
    parentSpanId: String?,
    durationMillis: Long,
    status: String,
    attributes: Map<String, String>,
  ) {
    val record = SpanRecord(
      name = name,
      traceId = context.traceId,
      spanId = context.spanId,
      parentSpanId = parentSpanId,
      durationMillis = durationMillis.coerceAtLeast(0),
      status = status,
      attributes = AttributePolicy.sanitize(attributes),
    )
    lock.withLock { spanList.add(record) }
  }

  internal fun recordError(code: String, stage: String, attributes: Map<String, String> = emptyMap()) {
    recordEvent("client.error", code, stage, attributes)
  }

  internal fun recordEvent(name: String, code: String, stage: String, attributes: Map<String, String> = emptyMap()) {
    val event = TelemetryEvent(
      name = name,
      errorCode = AttributePolicy.safeCode(code),
      failureStage = AttributePolicy.safeStage(stage),
      attributes = AttributePolicy.sanitize(attributes),
    )
    lock.withLock { eventList.add(event) }
  }

  internal fun observeSessionHealth(report: SessionHealthReport, durationMillis: Long) {
    lock.withLock {
      val previous = connection
      var emittedCorridor = false
      if (previous != report.connectionState) {
        connection = report.connectionState
        eventList.add(
          TelemetryEvent(
            name = "session.connection_changed",
            errorCode = report.httpStatus?.let { "HTTP_$it" } ?: "NONE",
            failureStage = "session_health",
            attributes = AttributePolicy.sanitize(
              mapOf(
                "connection.previous" to previous,
                "connection.current" to report.connectionState,
                "http.status_code" to (report.httpStatus?.toString() ?: ""),
                "duration_ms" to durationMillis.coerceAtLeast(0).toString(),
              ),
            ),
          ),
        )
      }
      for (corridor in report.corridors) {
        val prior = corridorStates[corridor.id] ?: "unknown"
        if (prior == corridor.state) continue
        corridorStates[corridor.id] = corridor.state
        if (corridor.state == "degraded" || corridor.state == "down") {
          emittedCorridor = true
          val attributes = mutableMapOf(
            "corridor.id" to corridor.id,
            "corridor.state" to corridor.state,
            "connection.previous" to prior,
            "connection.current" to corridor.state,
          )
          corridor.provider?.let { attributes["payment.provider"] = it }
          corridor.method?.let { attributes["payment.method"] = it }
          eventList.add(
            TelemetryEvent(
              name = "corridor.degraded",
              errorCode = "CORRIDOR_${corridor.state.uppercase()}",
              failureStage = "session_health",
              attributes = AttributePolicy.sanitize(attributes),
            ),
          )
        }
      }
      val worsened = report.connectionState == "degraded" || report.connectionState == "unreachable"
      if (worsened && previous != report.connectionState && !emittedCorridor && report.corridors.isEmpty()) {
        eventList.add(
          TelemetryEvent(
            name = "corridor.degraded",
            errorCode = "CORRIDOR_${report.connectionState.uppercase()}",
            failureStage = "session_health",
            attributes = AttributePolicy.sanitize(
              mapOf(
                "corridor.id" to "session",
                "corridor.state" to if (report.connectionState == "unreachable") "down" else "degraded",
                "connection.previous" to previous,
                "connection.current" to report.connectionState,
              ),
            ),
          ),
        )
      }
    }
  }
}

internal object AttributePolicy {
  private val allowed = setOf(
    "http.route",
    "http.method",
    "http.status_code",
    "payment.method",
    "payment.provider",
    "outcome",
    "corridor.id",
    "corridor.state",
    "connection.previous",
    "connection.current",
    "recipient.count",
    "provider.count",
    "duration_ms",
    "error.message",
  )

  fun sanitize(input: Map<String, String>): Map<String, String> {
    val output = linkedMapOf<String, String>()
    for ((key, value) in input) {
      if (key !in allowed) continue
      val cleaned = clean(key, value)
      if (cleaned.isNotEmpty()) output[key] = cleaned
    }
    return output
  }

  fun safeCode(code: String): String {
    val token = code.trim()
    if (!token.matches(Regex("^[A-Za-z0-9_]{1,64}$"))) return "REDACTED_CODE"
    return if (TelemetrySanitizer.containsSensitive(token)) "REDACTED_CODE" else token
  }

  fun safeStage(stage: String): String {
    val token = stage.trim()
    return if (token.matches(Regex("^[a-z0-9_]{1,64}$"))) token else "unknown"
  }

  private fun clean(key: String, value: String): String {
    return when (key) {
      "payment.provider" -> if (value == "adyen" || value == "worldpay") value else ""
      "payment.method" -> if (value == "card" || value == "bank") value else ""
      "http.status_code", "recipient.count", "provider.count", "duration_ms" ->
        if (value.matches(Regex("^[0-9]{1,12}$"))) value else ""
      "http.method" -> if (value.matches(Regex("^[A-Z]{1,8}$"))) value else ""
      "error.message" -> TelemetrySanitizer.redact(value).take(180)
      "corridor.id" -> if (value == "adyen-card" || value == "worldpay-bank" || value == "session") value else ""
      "corridor.state", "connection.previous", "connection.current" -> {
        val redacted = TelemetrySanitizer.redact(value)
        if (redacted.matches(Regex("^[a-z0-9_.:-]{1,64}$"))) redacted else ""
      }
      "outcome" -> {
        val redacted = TelemetrySanitizer.redact(value)
        if (redacted.matches(Regex("^[A-Za-z0-9_.:-]{1,64}$")) && !TelemetrySanitizer.containsSensitive(redacted)) {
          redacted
        } else {
          ""
        }
      }
      else -> TelemetrySanitizer.redact(value).take(80)
    }
  }
}
