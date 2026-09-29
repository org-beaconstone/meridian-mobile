package com.atlassian.meridian

import java.security.SecureRandom

/**
 * In-process W3C Trace Context and structured telemetry.
 * Spans stay on the device. Nothing is exported to a collector, and no provider network call is made.
 */
class TelemetryLog {
  private val lock = Any()
  private val spanRecords = mutableListOf<SpanRecord>()
  private val eventRecords = mutableListOf<TelemetryEvent>()

  fun startSpan(
    name: String,
    traceId: String = TraceIds.hex(16),
    parentSpanId: String? = null,
  ): OpenSpan = OpenSpan(
    name = name,
    traceId = traceId,
    spanId = TraceIds.hex(8),
    parentSpanId = parentSpanId,
    startedNanos = System.nanoTime(),
    log = this,
  )

  internal fun addSpan(record: SpanRecord) {
    synchronized(lock) { spanRecords.add(record) }
  }

  fun recordError(
    code: String,
    stage: String,
    message: String,
    traceId: String,
    spanId: String,
    attributes: Map<String, String> = emptyMap(),
  ) {
    record(
      TelemetryEvent(
        name = "client.error",
        code = Sanitizer.sanitize(code).take(80),
        stage = stage,
        message = Sanitizer.sanitize(message).take(180),
        traceId = traceId,
        spanId = spanId,
        attributes = Sanitizer.cleanAttributes(attributes),
      )
    )
  }

  fun record(event: TelemetryEvent) {
    val safe = event.copy(
      code = Sanitizer.sanitize(event.code).take(80),
      message = Sanitizer.sanitize(event.message).take(180),
      attributes = Sanitizer.cleanAttributes(event.attributes),
    )
    synchronized(lock) { eventRecords.add(safe) }
  }

  fun spans(): List<SpanRecord> = synchronized(lock) { spanRecords.toList() }

  fun events(): List<TelemetryEvent> = synchronized(lock) { eventRecords.toList() }
}

class OpenSpan internal constructor(
  val name: String,
  val traceId: String,
  val spanId: String,
  val parentSpanId: String?,
  private val startedNanos: Long,
  private val log: TelemetryLog,
) {
  private var ended = false

  fun traceparent(): String = TraceIds.traceparent(traceId, spanId)

  fun end(status: String, attributes: Map<String, String> = emptyMap()): SpanRecord {
    check(!ended) { "Span $name already ended" }
    ended = true
    val durationNanos = (System.nanoTime() - startedNanos).coerceAtLeast(0)
    val record = SpanRecord(
      name = name,
      traceId = traceId,
      spanId = spanId,
      parentSpanId = parentSpanId,
      durationMillis = durationNanos / 1_000_000,
      status = status,
      attributes = Sanitizer.cleanAttributes(attributes),
    )
    log.addSpan(record)
    return record
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
  val code: String,
  val stage: String,
  val message: String,
  val traceId: String,
  val spanId: String,
  val attributes: Map<String, String> = emptyMap(),
)

data class BiometricResolution(
  val outcome: String,
  val code: String?,
)

data class CorridorStatus(
  val id: String,
  val state: String,
)

data class SessionHealthSnapshot(
  val connection: String,
  val corridors: List<CorridorStatus>,
) {
  fun summary(): String {
    val degraded = corridors.filter { it.state == "degraded" || it.state == "down" }
    return if (degraded.isEmpty()) {
      "Session health: $connection"
    } else {
      "Session health: $connection · " + degraded.joinToString { "${it.id} ${it.state}" }
    }
  }
}

object TraceIds {
  private val random = SecureRandom()
  private val hex = "0123456789abcdef".toCharArray()
  private val traceparentPattern = Regex("^00-[0-9a-f]{32}-[0-9a-f]{16}-01$")

  fun hex(numBytes: Int): String {
    repeat(4) {
      val bytes = ByteArray(numBytes)
      random.nextBytes(bytes)
      val value = CharArray(numBytes * 2)
      for (index in bytes.indices) {
        val current = bytes[index].toInt() and 0xff
        value[index * 2] = hex[current ushr 4]
        value[index * 2 + 1] = hex[current and 0x0f]
      }
      val encoded = String(value)
      if (encoded.any { it != '0' }) return encoded
    }
    return "1".padStart(numBytes * 2, '0')
  }

  fun traceparent(traceId: String, spanId: String): String = "00-$traceId-$spanId-01"

  fun isTraceparent(value: String): Boolean = traceparentPattern.matches(value)
}

object Sanitizer {
  private val ibanPrefix = Regex("""(?i)(?<![A-Za-z0-9])[A-Z]{2}\d{2}""")
  private val panCandidate = Regex("""(?<![0-9])(?:\d[ -]?){12,18}\d(?![0-9])""")
  private val forbiddenKeys = setOf(
    "pan",
    "iban",
    "card",
    "cardnumber",
    "accountnumber",
    "cvv",
    "cvc",
    "note",
    "detail",
    "recipientdetail",
  )

  fun sanitize(input: String): String {
    if (input.isEmpty()) return input
    return panCandidate.replace(scrubIbans(input)) { match ->
      val digits = match.value.filter { it.isDigit() }
      if (digits.length in 13..19 && luhn(digits)) "[REDACTED_PAN]" else match.value
    }
  }

  private fun scrubIbans(input: String): String {
    val result = StringBuilder()
    var index = 0
    while (index < input.length) {
      val match = ibanPrefix.find(input, index) ?: break
      val start = match.range.first
      result.append(input, index, start)
      var cursor = match.range.last + 1
      var accepted = -1
      while (cursor <= input.length) {
        val candidate = input.substring(start, cursor)
        val compactLength = candidate.count { !it.isWhitespace() }
        if (compactLength >= 15 && isIban(candidate)) accepted = cursor
        if (cursor == input.length || compactLength >= 34) break
        val next = input[cursor]
        if (next == ' ') {
          if (cursor + 1 < input.length && input[cursor + 1].isLetterOrDigit()) {
            cursor += 1
            continue
          }
          break
        }
        if (!next.isLetterOrDigit()) break
        cursor += 1
      }
      if (accepted > start) {
        result.append("[REDACTED_IBAN]")
        index = accepted
      } else {
        result.append(match.value)
        index = match.range.last + 1
      }
    }
    result.append(input.substring(index))
    return result.toString()
  }

  fun cleanAttributes(input: Map<String, String>): Map<String, String> {
    val cleaned = linkedMapOf<String, String>()
    for ((key, value) in input) {
      val normalized = key.lowercase().replace("_", "").replace("-", "")
      if (normalized in forbiddenKeys || normalized.contains("pan") || normalized.contains("iban")) continue
      cleaned[key] = sanitize(value).take(180)
    }
    return cleaned
  }

  fun isIban(candidate: String): Boolean {
    val compact = candidate.replace(" ", "").uppercase()
    if (compact.length !in 15..34) return false
    if (!compact.matches(Regex("[A-Z]{2}[0-9]{2}[A-Z0-9]+"))) return false
    val rearranged = compact.drop(4) + compact.take(4)
    val numeric = buildString {
      for (character in rearranged) {
        if (character.isDigit()) append(character)
        else append(character.code - 'A'.code + 10)
      }
    }
    return mod97(numeric) == 1
  }

  fun luhn(digits: String): Boolean {
    if (digits.isEmpty() || digits.any { !it.isDigit() }) return false
    var sum = 0
    var alternate = false
    for (index in digits.length - 1 downTo 0) {
      var current = digits[index].digitToInt()
      if (alternate) {
        current *= 2
        if (current > 9) current -= 9
      }
      sum += current
      alternate = !alternate
    }
    return sum % 10 == 0
  }

  private fun mod97(numeric: String): Int {
    var remainder = 0
    for (character in numeric) {
      remainder = (remainder * 10 + (character.code - '0'.code)) % 97
    }
    return remainder
  }
}

object CorridorIds {
  private val cardIds = setOf("adyen", "card", "adyen-card")
  private val bankIds = setOf("worldpay", "bank", "worldpay-bank")

  fun canonical(id: String?, provider: String?): String {
    val candidates = listOfNotNull(id, provider).map { it.trim().lowercase() }.filter { it.isNotEmpty() }
    if (candidates.any { it in bankIds }) return "worldpay-bank"
    if (candidates.any { it in cardIds }) return "adyen-card"
    return "corridor"
  }

  fun state(state: String?, status: String?): String {
    val raw = (state ?: status ?: "unknown").trim().lowercase()
    return when (raw) {
      "healthy", "ok", "up" -> "healthy"
      "degraded", "impaired" -> "degraded"
      "down", "unavailable", "failed" -> "down"
      else -> "unknown"
    }
  }

  fun connection(explicit: String?, status: String?, corridors: List<CorridorStatus>): String {
    val normalized = explicit?.trim()?.lowercase()
    val degraded = corridors.any { it.state == "degraded" || it.state == "down" }
    if (normalized == "disconnected" || normalized == "down") return "disconnected"
    if (normalized == "degraded" || degraded) return "degraded"
    if (normalized == "connected" || normalized == "up") return "connected"
    return when (status?.trim()?.uppercase()) {
      "DOWN", "UNAVAILABLE" -> "disconnected"
      else -> "connected"
    }
  }
}
