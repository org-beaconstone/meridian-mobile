package com.atlassian.meridian

import java.security.SecureRandom
import kotlin.math.max

/**
 * OpenTelemetry-style spans and W3C Trace Context for the native payment SDK.
 * Outbound traceparent values keep the upstream gateway trace id so client spans
 * join that trace tree. This type never calls PagerDuty or a payment provider.
 */
object MeridianTelemetryLimit {
  const val paymentSubmissionP95Ms: Long = 1_200
  const val biometricPromptMs: Long = 300
  const val submissionErrorRatePercent: Int = 1
  const val pagerWindowMs: Long = 5 * 60 * 1000
  const val scaDropOffPercent: Int = 5
}

data class BiometricPromptResult(
  val durationMs: Long,
  val withinSlo: Boolean,
)

data class LatencySloReport(
  val metric: String,
  val thresholdMs: Long,
  val observedMs: Long?,
  val withinSlo: Boolean,
  val samples: Int,
)

data class AlertDecision(
  val shouldPage: Boolean,
  val reasons: List<String>,
  val submissionErrorRate: Double?,
  val scaDropOffRate: Double?,
)

data class SpanSnapshot(
  val name: String,
  val traceId: String,
  val spanId: String,
  val parentSpanId: String?,
  val traceparent: String,
  val tracestate: String?,
  val startMs: Long,
  val endMs: Long?,
  val durationMs: Long,
  val status: String,
  val attributes: Map<String, String>,
)

data class TelemetrySnapshot(
  val traceId: String,
  val spans: List<SpanSnapshot>,
  val errorLogs: List<String>,
  val breadcrumbs: List<String>,
  val paymentSlo: LatencySloReport,
  val biometricSlo: LatencySloReport,
  val alerts: AlertDecision,
)

internal data class TraceContext(
  val traceId: String,
  val spanId: String,
  val sampled: Boolean,
  val tracestate: String?,
) {
  val traceparent: String
    get() = "00-$traceId-$spanId-${if (sampled) "01" else "00"}"

  fun child(vendor: String): TraceContext = TraceContext(
    traceId = traceId,
    spanId = TraceRandom.hex(8),
    sampled = sampled,
    tracestate = merge(vendor, tracestate),
  )

  companion object {
    fun parse(header: String): TraceContext? {
      val parts = header.trim().split("-")
      if (parts.size != 4) return null
      val version = parts[0]
      val trace = parts[1]
      val span = parts[2]
      val flags = parts[3]
      if (version != "00") return null
      if (trace.length != 32 || span.length != 16 || flags.length != 2) return null
      if (!isHex(trace) || !isHex(span) || !isHex(flags)) return null
      if (!notAllZero(trace) || !notAllZero(span)) return null
      val sampled = (flags.toInt(16) and 0x1) == 1
      return TraceContext(trace.lowercase(), span.lowercase(), sampled, null)
    }

    fun newRoot(vendor: String): TraceContext = TraceContext(
      traceId = TraceRandom.hex(16),
      spanId = TraceRandom.hex(8),
      sampled = true,
      tracestate = "meridian=$vendor",
    )

    fun merge(vendor: String, existing: String?): String {
      val entry = "meridian=$vendor"
      if (existing.isNullOrEmpty()) return entry
      val kept = existing.split(",").map { it.trim() }.filter { it.isNotEmpty() && !it.startsWith("meridian=") }
      return (listOf(entry) + kept).joinToString(",")
    }

    private fun isHex(value: String) = value.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }

    private fun notAllZero(value: String) = value.any { it != '0' }
  }
}

private object TraceRandom {
  private val random = SecureRandom()

  fun hex(bytes: Int): String {
    val buffer = ByteArray(bytes)
    random.nextBytes(buffer)
    if (buffer.all { it == 0.toByte() }) buffer[0] = 1
    return buffer.joinToString("") { "%02x".format(it) }
  }
}

class OpenSpan internal constructor(
  val name: String,
  internal val context: TraceContext,
  val parentSpanId: String?,
  val startMs: Long,
) {
  val attributes: MutableMap<String, String> = linkedMapOf()
  internal var ended: Boolean = false
  internal var status: String = "open"
  internal var endMs: Long? = null
  internal var durationMs: Long = 0

  val traceId: String get() = context.traceId
  val spanId: String get() = context.spanId
  val traceparent: String get() = context.traceparent
  val tracestate: String? get() = context.tracestate

  fun snapshot(): SpanSnapshot = SpanSnapshot(
    name = name,
    traceId = traceId,
    spanId = spanId,
    parentSpanId = parentSpanId,
    traceparent = traceparent,
    tracestate = tracestate,
    startMs = startMs,
    endMs = endMs,
    durationMs = durationMs,
    status = status,
    attributes = attributes.toMap(),
  )
}

object TelemetrySanitizer {
  fun sanitize(input: String): String = redactPans(redactIbans(redactLabeled(input)))

  private val labeled = listOf(
    Regex("(?i)\\b(card\\s*holder(?:\\s*name)?|name\\s*on\\s*card)\\b\\s*[:=]\\s*[^,\\n;]{1,80}"),
    Regex("(?i)\\b(cvv|cvc2|cvc|cid|security\\s*code)\\b\\s*[:=]?\\s*\\d{3,4}\\b"),
    Regex("(?i)\\b(expiry|expiration|exp)\\b\\s*[:=]?\\s*\\d{1,2}\\s*[/\\-]\\s*\\d{2,4}\\b"),
  )

  private fun redactLabeled(input: String): String {
    var text = input
    labeled.forEach { pattern ->
      text = pattern.replace(text, "[REDACTED_CARDHOLDER]")
    }
    return text
  }

  private fun redactIbans(input: String): String {
    val chars = input.toCharArray()
    val output = StringBuilder()
    var index = 0
    while (index < chars.size) {
      val end = ibanEnd(chars, index)
      if (end != null) {
        output.append("[REDACTED_IBAN]")
        index = end
      } else {
        output.append(chars[index])
        index += 1
      }
    }
    return output.toString()
  }

  private fun redactPans(input: String): String {
    val chars = input.toCharArray()
    val output = StringBuilder()
    var index = 0
    while (index < chars.size) {
      if (isDigit(chars[index]) && (index == 0 || !isDigit(chars[index - 1]))) {
        var cursor = index
        val digits = StringBuilder()
        while (cursor < chars.size && digits.length < 19) {
          val character = chars[cursor]
          if (isDigit(character)) {
            digits.append(character)
            cursor += 1
          } else if ((character == ' ' || character == '-') &&
            cursor + 1 < chars.size &&
            isDigit(chars[cursor + 1]) &&
            digits.isNotEmpty()
          ) {
            cursor += 1
          } else {
            break
          }
        }
        val continues = cursor < chars.size && (
          isDigit(chars[cursor]) ||
            ((chars[cursor] == ' ' || chars[cursor] == '-') && cursor + 1 < chars.size && isDigit(chars[cursor + 1]))
          )
        if (!continues && digits.length in 13..19 && luhn(digits.toString())) {
          output.append("[REDACTED_PAN]")
          index = cursor
          continue
        }
      }
      output.append(chars[index])
      index += 1
    }
    return output.toString()
  }

  private fun ibanEnd(chars: CharArray, start: Int): Int? {
    if (!isIbanStart(chars, start)) return null
    val chunks = mutableListOf<String>()
    val current = StringBuilder()
    var index = start
    while (index < chars.size) {
      val character = chars[index]
      if (isLetter(character) || isDigit(character)) {
        current.append(character)
        if (current.length > 34) break
        index += 1
      } else if (character == ' ' &&
        current.isNotEmpty() &&
        index + 1 < chars.size &&
        (isLetter(chars[index + 1]) || isDigit(chars[index + 1]))
      ) {
        chunks += current.toString()
        current.clear()
        index += 1
      } else {
        break
      }
    }
    if (current.isNotEmpty()) chunks += current.toString()
    while (chunks.isNotEmpty()) {
      val joined = chunks.joinToString("")
      if (joined.length in 15..34 && isValidIban(joined)) {
        val original = chunks.sumOf { it.length } + chunks.size - 1
        return start + original
      }
      var last = chunks.removeAt(chunks.lastIndex)
      last = last.dropLast(1)
      if (last.isNotEmpty()) chunks += last
    }
    return null
  }

  private fun isIbanStart(chars: CharArray, index: Int): Boolean {
    if (index + 3 >= chars.size) return false
    if (index > 0 && (isLetter(chars[index - 1]) || isDigit(chars[index - 1]))) return false
    return isLetter(chars[index]) && isLetter(chars[index + 1]) && isDigit(chars[index + 2]) && isDigit(chars[index + 3])
  }

  private fun isValidIban(raw: String): Boolean {
    val compact = raw.uppercase()
    if (compact.length !in 15..34) return false
    if (!compact.matches(Regex("^[A-Z]{2}[0-9]{2}[A-Z0-9]+$"))) return false
    val moved = compact.drop(4) + compact.take(4)
    var remainder = 0
    for (character in moved) {
      val value = if (character.isDigit()) {
        character.toString()
      } else if (character in 'A'..'Z') {
        (character.code - 'A'.code + 10).toString()
      } else {
        return false
      }
      for (digit in value) {
        remainder = (remainder * 10 + (digit - '0')) % 97
      }
    }
    return remainder == 1
  }

  private fun luhn(digits: String): Boolean {
    var sum = 0
    var alternate = false
    for (character in digits.reversed()) {
      var number = character.digitToIntOrNull() ?: return false
      if (alternate) {
        number *= 2
        if (number > 9) number -= 9
      }
      sum += number
      alternate = !alternate
    }
    return digits.isNotEmpty() && sum % 10 == 0
  }

  private fun isDigit(character: Char) = character in '0'..'9'

  private fun isLetter(character: Char) = character in 'A'..'Z' || character in 'a'..'z'
}

private data class TimedFlag(val atMs: Long, val flagged: Boolean)

class TelemetryCenter(
  upstreamTraceparent: String? = null,
  upstreamTracestate: String? = null,
  private val vendor: String = "sdk-android",
  language: String = "kotlin",
  sessionId: String? = null,
  private val now: () -> Long = { System.currentTimeMillis() },
) {
  private val lock = Any()
  private val sessionSpan: OpenSpan
  private val open = mutableListOf<OpenSpan>()
  private val completed = mutableListOf<OpenSpan>()
  private val errorLogs = mutableListOf<String>()
  private val breadcrumbs = mutableListOf<String>()
  private val paymentSamples = mutableListOf<Long>()
  private val biometricSamples = mutableListOf<Long>()
  private val submissions = mutableListOf<TimedFlag>()
  private val scaEvents = mutableListOf<TimedFlag>()

  val traceId: String
  val sessionSpanId: String

  init {
    val parsed = upstreamTraceparent?.let { TraceContext.parse(it) }?.copy(tracestate = upstreamTracestate)
    val sessionContext: TraceContext
    val parentSpanId: String?
    if (parsed != null) {
      sessionContext = parsed.child(vendor)
      parentSpanId = parsed.spanId
    } else {
      sessionContext = TraceContext.newRoot(vendor)
      parentSpanId = null
    }
    sessionSpan = OpenSpan("meridian.session", sessionContext, parentSpanId, now())
    sessionSpan.attributes["telemetry.sdk.name"] = "meridian-mobile"
    sessionSpan.attributes["telemetry.sdk.language"] = language
    sessionSpan.attributes["span.kind"] = "internal"
    if (sessionId != null) {
      sessionSpan.attributes["meridian.rehearsal_session"] = TelemetrySanitizer.sanitize(sessionId)
    }
    traceId = sessionSpan.traceId
    sessionSpanId = sessionSpan.spanId
    open += sessionSpan
  }

  fun startSpan(name: String, parent: OpenSpan? = null): OpenSpan = synchronized(lock) {
    val parentSpan = parent ?: sessionSpan
    val span = OpenSpan(
      name,
      parentSpan.context.child(vendor),
      parentSpan.spanId,
      now(),
    )
    open += span
    span
  }

  fun startHttpSpan(method: String, path: String, parent: OpenSpan? = null): OpenSpan {
    val span = startSpan("HTTP $method $path", parent)
    setAttribute(span, "http.request.method", method)
    setAttribute(span, "url.path", path)
    setAttribute(span, "span.kind", "client")
    return span
  }

  fun setAttribute(span: OpenSpan, key: String, value: String) {
    synchronized(lock) {
      span.attributes[key] = TelemetrySanitizer.sanitize(value)
    }
  }

  fun noteError(span: OpenSpan, message: String) {
    val clean = TelemetrySanitizer.sanitize(message)
    synchronized(lock) {
      errorLogs += clean
      breadcrumbs += "${span.name}: $clean"
    }
  }

  fun addBreadcrumb(message: String) {
    synchronized(lock) {
      breadcrumbs += TelemetrySanitizer.sanitize(message)
    }
  }

  fun endSpan(span: OpenSpan, status: String, durationMs: Long? = null): SpanSnapshot = synchronized(lock) {
    if (span.ended) return span.snapshot()
    val duration = durationMs?.let { max(0, it) } ?: max(0, now() - span.startMs)
    span.ended = true
    span.status = status
    span.durationMs = duration
    span.endMs = span.startMs + duration
    span.attributes["slo.sample_ms"] = duration.toString()
    if (span.name == "payment.submit" && (status == "ok" || status == "error")) {
      span.attributes["slo.metric"] = "p95"
      span.attributes["slo.threshold_ms"] = MeridianTelemetryLimit.paymentSubmissionP95Ms.toString()
      paymentSamples += duration
      submissions += TimedFlag(now(), status == "error")
    }
    if (span.name == "biometric.prompt") {
      val breach = duration >= MeridianTelemetryLimit.biometricPromptMs
      span.attributes["slo.metric"] = "latency"
      span.attributes["slo.threshold_ms"] = MeridianTelemetryLimit.biometricPromptMs.toString()
      span.attributes["slo.breach"] = if (breach) "true" else "false"
      biometricSamples += duration
    }
    open.removeAll { it === span }
    completed += span
    span.snapshot()
  }

  fun recordSubmission(success: Boolean) {
    synchronized(lock) {
      submissions += TimedFlag(now(), !success)
    }
  }

  fun recordSca(dropped: Boolean, detail: String = "") {
    val clean = TelemetrySanitizer.sanitize(detail)
    val suffix = if (clean.isEmpty()) "" else " $clean"
    synchronized(lock) {
      scaEvents += TimedFlag(now(), dropped)
      breadcrumbs += if (dropped) "sca dropped$suffix" else "sca completed$suffix"
    }
  }

  fun recordBiometricPrompt(durationMs: Long): BiometricPromptResult {
    val span = startSpan("biometric.prompt")
    val snapshot = endSpan(span, "ok", durationMs)
    return BiometricPromptResult(snapshot.durationMs, snapshot.durationMs < MeridianTelemetryLimit.biometricPromptMs)
  }

  fun measureBiometricPrompt(): BiometricPromptResult {
    val span = startSpan("biometric.prompt")
    val snapshot = endSpan(span, "ok")
    return BiometricPromptResult(snapshot.durationMs, snapshot.durationMs < MeridianTelemetryLimit.biometricPromptMs)
  }

  fun paymentSlo(): LatencySloReport = synchronized(lock) { paymentSloLocked() }

  fun biometricSlo(): LatencySloReport = synchronized(lock) { biometricSloLocked() }

  fun evaluateAlerts(): AlertDecision = synchronized(lock) { evaluateLocked(now()) }

  fun snapshot(): TelemetrySnapshot = synchronized(lock) {
    TelemetrySnapshot(
      traceId = traceId,
      spans = (open + completed).map { it.snapshot() },
      errorLogs = errorLogs.toList(),
      breadcrumbs = breadcrumbs.toList(),
      paymentSlo = paymentSloLocked(),
      biometricSlo = biometricSloLocked(),
      alerts = evaluateLocked(now()),
    )
  }

  private fun paymentSloLocked(): LatencySloReport {
    if (paymentSamples.isEmpty()) {
      return LatencySloReport("p95", MeridianTelemetryLimit.paymentSubmissionP95Ms, null, true, 0)
    }
    val observed = percentile95(paymentSamples)
    return LatencySloReport(
      "p95",
      MeridianTelemetryLimit.paymentSubmissionP95Ms,
      observed,
      observed < MeridianTelemetryLimit.paymentSubmissionP95Ms,
      paymentSamples.size,
    )
  }

  private fun biometricSloLocked(): LatencySloReport {
    val observed = biometricSamples.maxOrNull()
      ?: return LatencySloReport("latency", MeridianTelemetryLimit.biometricPromptMs, null, true, 0)
    return LatencySloReport(
      "latency",
      MeridianTelemetryLimit.biometricPromptMs,
      observed,
      observed < MeridianTelemetryLimit.biometricPromptMs,
      biometricSamples.size,
    )
  }

  private fun evaluateLocked(atMs: Long): AlertDecision {
    val windowStart = atMs - MeridianTelemetryLimit.pagerWindowMs
    val recentSubmissions = submissions.filter { it.atMs in windowStart..atMs }
    val recentSca = scaEvents.filter { it.atMs in windowStart..atMs }
    val failures = recentSubmissions.count { it.flagged }
    val dropped = recentSca.count { it.flagged }
    val reasons = mutableListOf<String>()
    if (recentSubmissions.isNotEmpty() &&
      failures * 100 > recentSubmissions.size * MeridianTelemetryLimit.submissionErrorRatePercent
    ) {
      reasons += "submission error rate ${formatPercent(failures, recentSubmissions.size)} exceeds 1.0% over 5 minutes"
    }
    if (recentSca.isNotEmpty() && dropped * 100 > recentSca.size * MeridianTelemetryLimit.scaDropOffPercent) {
      reasons += "SCA drop-offs ${formatPercent(dropped, recentSca.size)} exceed 5%"
    }
    return AlertDecision(
      shouldPage = reasons.isNotEmpty(),
      reasons = reasons.toList(),
      submissionErrorRate = if (recentSubmissions.isEmpty()) null else failures.toDouble() / recentSubmissions.size,
      scaDropOffRate = if (recentSca.isEmpty()) null else dropped.toDouble() / recentSca.size,
    )
  }
}

private fun percentile95(values: List<Long>): Long {
  val sorted = values.sorted()
  val count = sorted.size
  val rank = (count * 95 + 99) / 100
  return sorted[(rank.coerceIn(1, count)) - 1]
}

private fun formatPercent(numerator: Int, denominator: Int): String {
  val scaled = if (denominator == 0) 0 else (numerator * 10_000) / denominator
  return "%d.%02d%%".format(scaled / 100, scaled % 100)
}
