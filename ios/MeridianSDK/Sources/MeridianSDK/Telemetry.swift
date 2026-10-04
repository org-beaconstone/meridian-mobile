import Foundation

/// OpenTelemetry-style spans and W3C Trace Context for the native payment SDK.
/// Outbound `traceparent` values use the same trace id as an upstream gateway span
/// so client work joins that trace tree. Nothing here contacts PagerDuty or a provider.

public enum MeridianTelemetryLimit {
  public static let paymentSubmissionP95Ms: Int64 = 1_200
  public static let biometricPromptMs: Int64 = 300
  public static let submissionErrorRatePercent: Int = 1
  public static let pagerWindowMs: Int64 = 5 * 60 * 1000
  public static let scaDropOffPercent: Int = 5
}

public struct BiometricPromptResult: Equatable, Sendable {
  public let durationMs: Int64
  public let withinSlo: Bool
}

public struct LatencySloReport: Equatable, Sendable {
  public let metric: String
  public let thresholdMs: Int64
  public let observedMs: Int64?
  public let withinSlo: Bool
  public let samples: Int
}

public struct AlertDecision: Equatable, Sendable {
  public let shouldPage: Bool
  public let reasons: [String]
  public let submissionErrorRate: Double?
  public let scaDropOffRate: Double?
}

public struct SpanSnapshot: Equatable, Sendable {
  public let name: String
  public let traceId: String
  public let spanId: String
  public let parentSpanId: String?
  public let traceparent: String
  public let tracestate: String?
  public let startMs: Int64
  public let endMs: Int64?
  public let durationMs: Int64
  public let status: String
  public let attributes: [String: String]
}

public struct TelemetrySnapshot: Equatable, Sendable {
  public let traceId: String
  public let spans: [SpanSnapshot]
  public let errorLogs: [String]
  public let breadcrumbs: [String]
  public let paymentSlo: LatencySloReport
  public let biometricSlo: LatencySloReport
  public let alerts: AlertDecision
}

struct TraceContext {
  let traceId: String
  let spanId: String
  let sampled: Bool
  let tracestate: String?

  var traceparent: String {
    "00-\(traceId)-\(spanId)-\(sampled ? "01" : "00")"
  }

  static func parse(_ header: String) -> TraceContext? {
    let parts = header.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-")
    guard parts.count == 4 else { return nil }
    let version = parts[0]
    let trace = parts[1]
    let span = parts[2]
    let flags = parts[3]
    guard version == "00" else { return nil }
    guard trace.count == 32, span.count == 16, flags.count == 2 else { return nil }
    guard isHex(trace), isHex(span), isHex(flags) else { return nil }
    guard notAllZero(trace), notAllZero(span) else { return nil }
    let sampled = (Int(flags, radix: 16) ?? 0) & 0x1 == 1
    return TraceContext(
      traceId: trace.lowercased(),
      spanId: span.lowercased(),
      sampled: sampled,
      tracestate: nil
    )
  }

  static func newRoot(vendor: String) -> TraceContext {
    TraceContext(
      traceId: TraceRandom.hex(bytes: 16),
      spanId: TraceRandom.hex(bytes: 8),
      sampled: true,
      tracestate: "meridian=\(vendor)"
    )
  }

  func child(vendor: String) -> TraceContext {
    TraceContext(
      traceId: traceId,
      spanId: TraceRandom.hex(bytes: 8),
      sampled: sampled,
      tracestate: TraceContext.merge(vendor: vendor, existing: tracestate)
    )
  }

  static func merge(vendor: String, existing: String?) -> String {
    let entry = "meridian=\(vendor)"
    guard let existing, !existing.isEmpty else { return entry }
    let kept = existing.split(separator: ",").map(String.init).filter { part in
      !part.trimmingCharacters(in: .whitespaces).hasPrefix("meridian=")
    }
    return ([entry] + kept).joined(separator: ",")
  }

  private static func isHex(_ value: Substring) -> Bool {
    value.allSatisfy { $0.isHexDigit }
  }

  private static func notAllZero(_ value: Substring) -> Bool {
    value.contains { $0 != "0" }
  }
}

enum TraceRandom {
  static func hex(bytes: Int) -> String {
    var data = [UInt8](repeating: 0, count: bytes)
    for index in data.indices {
      data[index] = UInt8.random(in: .min ... .max)
    }
    if data.allSatisfy({ $0 == 0 }) {
      data[0] = 1
    }
    return data.map { String(format: "%02x", $0) }.joined()
  }
}

public final class OpenSpan {
  public let name: String
  let context: TraceContext
  public let parentSpanId: String?
  public let startMs: Int64
  var attributes: [String: String] = [:]
  var ended = false
  var status = "open"
  var endMs: Int64?
  var durationMs: Int64 = 0

  public var traceId: String { context.traceId }
  public var spanId: String { context.spanId }
  public var traceparent: String { context.traceparent }
  public var tracestate: String? { context.tracestate }

  init(name: String, context: TraceContext, parentSpanId: String?, startMs: Int64) {
    self.name = name
    self.context = context
    self.parentSpanId = parentSpanId
    self.startMs = startMs
  }

  func snapshot() -> SpanSnapshot {
    SpanSnapshot(
      name: name,
      traceId: traceId,
      spanId: spanId,
      parentSpanId: parentSpanId,
      traceparent: traceparent,
      tracestate: tracestate,
      startMs: startMs,
      endMs: endMs,
      durationMs: durationMs,
      status: status,
      attributes: attributes
    )
  }
}

public enum TelemetrySanitizer {
  public static func sanitize(_ input: String) -> String {
    redactPans(redactIbans(redactLabeled(input)))
  }

  private static func redactLabeled(_ input: String) -> String {
    let patterns = [
      #"(?i)\b(card\s*holder(?:\s*name)?|name\s*on\s*card)\b\s*[:=]\s*[^,\n;]{1,80}"#,
      #"(?i)\b(cvv|cvc2|cvc|cid|security\s*code)\b\s*[:=]?\s*\d{3,4}\b"#,
      #"(?i)\b(expiry|expiration|exp)\b\s*[:=]?\s*\d{1,2}\s*[/\-]\s*\d{2,4}\b"#,
    ]
    var text = input
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      let range = NSRange(text.startIndex..., in: text)
      text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "[REDACTED_CARDHOLDER]")
    }
    return text
  }

  private static func redactIbans(_ input: String) -> String {
    let chars = Array(input)
    var output = ""
    var index = 0
    while index < chars.count {
      if let end = ibanEnd(chars, index) {
        output += "[REDACTED_IBAN]"
        index = end
      } else {
        output.append(chars[index])
        index += 1
      }
    }
    return output
  }

  private static func redactPans(_ input: String) -> String {
    let chars = Array(input)
    var output = ""
    var index = 0
    while index < chars.count {
      if isDigit(chars[index]), index == 0 || !isDigit(chars[index - 1]) {
        var cursor = index
        var digits = ""
        while cursor < chars.count, digits.count < 19 {
          let character = chars[cursor]
          if isDigit(character) {
            digits.append(character)
            cursor += 1
          } else if (character == " " || character == "-"),
                    cursor + 1 < chars.count,
                    isDigit(chars[cursor + 1]),
                    !digits.isEmpty {
            cursor += 1
          } else {
            break
          }
        }
        let continues = cursor < chars.count && (
          isDigit(chars[cursor]) ||
            ((chars[cursor] == " " || chars[cursor] == "-") && cursor + 1 < chars.count && isDigit(chars[cursor + 1]))
        )
        if !continues, (13 ... 19).contains(digits.count), luhn(digits) {
          output += "[REDACTED_PAN]"
          index = cursor
          continue
        }
      }
      output.append(chars[index])
      index += 1
    }
    return output
  }

  private static func ibanEnd(_ chars: [Character], _ start: Int) -> Int? {
    guard isIbanStart(chars, start) else { return nil }
    var chunks: [String] = []
    var current = ""
    var index = start
    while index < chars.count {
      let character = chars[index]
      if isLetter(character) || isDigit(character) {
        current.append(character)
        if current.count > 34 { break }
        index += 1
      } else if character == " ",
                !current.isEmpty,
                index + 1 < chars.count,
                isLetter(chars[index + 1]) || isDigit(chars[index + 1]) {
        chunks.append(current)
        current = ""
        index += 1
      } else {
        break
      }
    }
    if !current.isEmpty {
      chunks.append(current)
    }
    while !chunks.isEmpty {
      let joined = chunks.joined()
      if (15 ... 34).contains(joined.count), isValidIban(joined) {
        let original = chunks.reduce(0) { $0 + $1.count } + chunks.count - 1
        return start + original
      }
      var last = chunks.removeLast()
      last.removeLast()
      if !last.isEmpty {
        chunks.append(last)
      }
    }
    return nil
  }

  private static func isIbanStart(_ chars: [Character], _ index: Int) -> Bool {
    guard index + 3 < chars.count else { return false }
    if index > 0, isLetter(chars[index - 1]) || isDigit(chars[index - 1]) { return false }
    return isLetter(chars[index]) && isLetter(chars[index + 1]) && isDigit(chars[index + 2]) && isDigit(chars[index + 3])
  }

  private static func isValidIban(_ raw: String) -> Bool {
    let compact = raw.uppercased()
    guard (15 ... 34).contains(compact.count) else { return false }
    guard compact.range(of: "^[A-Z]{2}[0-9]{2}[A-Z0-9]+$", options: .regularExpression) != nil else { return false }
    let moved = compact.dropFirst(4) + compact.prefix(4)
    var remainder = 0
    for character in moved {
      let value: String
      if let digit = character.wholeNumberValue, digit < 10 {
        value = String(digit)
      } else if let ascii = character.asciiValue, ascii >= 65, ascii <= 90 {
        value = String(Int(ascii) - 55)
      } else {
        return false
      }
      for digit in value {
        guard let number = digit.wholeNumberValue else { return false }
        remainder = (remainder * 10 + number) % 97
      }
    }
    return remainder == 1
  }

  private static func luhn(_ digits: String) -> Bool {
    var sum = 0
    var alternate = false
    for character in digits.reversed() {
      guard var number = character.wholeNumberValue else { return false }
      if alternate {
        number *= 2
        if number > 9 { number -= 9 }
      }
      sum += number
      alternate.toggle()
    }
    return !digits.isEmpty && sum % 10 == 0
  }

  private static func isDigit(_ character: Character) -> Bool {
    guard let ascii = character.asciiValue else { return false }
    return ascii >= 48 && ascii <= 57
  }

  private static func isLetter(_ character: Character) -> Bool {
    guard let ascii = character.asciiValue else { return false }
    return (ascii >= 65 && ascii <= 90) || (ascii >= 97 && ascii <= 122)
  }
}

private struct TimedFlag {
  let atMs: Int64
  let flagged: Bool
}

public final class TelemetryCenter {
  public let sessionSpanId: String
  public let traceId: String
  private let vendor: String
  private let now: () -> Int64
  private let sessionSpan: OpenSpan
  private var open: [OpenSpan] = []
  private var completed: [OpenSpan] = []
  private var errorLogs: [String] = []
  private var breadcrumbs: [String] = []
  private var paymentSamples: [Int64] = []
  private var biometricSamples: [Int64] = []
  private var submissions: [TimedFlag] = []
  private var scaEvents: [TimedFlag] = []

  public init(
    upstreamTraceparent: String? = nil,
    upstreamTracestate: String? = nil,
    vendor: String,
    language: String,
    sessionId: String? = nil,
    now: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1000.0).rounded()) }
  ) {
    self.vendor = vendor
    self.now = now
    let upstream = upstreamTraceparent.flatMap(TraceContext.parse)?.copying(tracestate: upstreamTracestate)
    let sessionContext: TraceContext
    let parentSpanId: String?
    if let upstream {
      sessionContext = upstream.child(vendor: vendor)
      parentSpanId = upstream.spanId
    } else {
      sessionContext = TraceContext.newRoot(vendor: vendor)
      parentSpanId = nil
    }
    let session = OpenSpan(name: "meridian.session", context: sessionContext, parentSpanId: parentSpanId, startMs: now())
    session.attributes["telemetry.sdk.name"] = "meridian-mobile"
    session.attributes["telemetry.sdk.language"] = language
    session.attributes["span.kind"] = "internal"
    if let sessionId {
      session.attributes["meridian.rehearsal_session"] = TelemetrySanitizer.sanitize(sessionId)
    }
    sessionSpan = session
    sessionSpanId = session.spanId
    traceId = session.traceId
    open.append(session)
  }

  public func startSpan(name: String, parent: OpenSpan? = nil) -> OpenSpan {
    let parentSpan = parent ?? sessionSpan
    let span = OpenSpan(
      name: name,
      context: parentSpan.context.child(vendor: vendor),
      parentSpanId: parentSpan.spanId,
      startMs: now()
    )
    open.append(span)
    return span
  }

  public func startHttpSpan(method: String, path: String, parent: OpenSpan? = nil) -> OpenSpan {
    let span = startSpan(name: "HTTP \(method) \(path)", parent: parent)
    setAttribute(span, "http.request.method", method)
    setAttribute(span, "url.path", path)
    setAttribute(span, "span.kind", "client")
    return span
  }

  public func setAttribute(_ span: OpenSpan, _ key: String, _ value: String) {
    span.attributes[key] = TelemetrySanitizer.sanitize(value)
  }

  public func noteError(_ span: OpenSpan, _ message: String) {
    let clean = TelemetrySanitizer.sanitize(message)
    errorLogs.append(clean)
    breadcrumbs.append("\(span.name): \(clean)")
  }

  public func addBreadcrumb(_ message: String) {
    breadcrumbs.append(TelemetrySanitizer.sanitize(message))
  }

  @discardableResult
  public func endSpan(_ span: OpenSpan, status: String, durationMs override: Int64? = nil) -> SpanSnapshot {
    guard !span.ended else { return span.snapshot() }
    let duration = override.map { max(Int64(0), $0) } ?? max(Int64(0), now() - span.startMs)
    span.ended = true
    span.status = status
    span.durationMs = duration
    span.endMs = span.startMs + duration
    span.attributes["slo.sample_ms"] = String(duration)
    if span.name == "payment.submit", status == "ok" || status == "error" {
      span.attributes["slo.metric"] = "p95"
      span.attributes["slo.threshold_ms"] = String(MeridianTelemetryLimit.paymentSubmissionP95Ms)
      paymentSamples.append(duration)
      submissions.append(TimedFlag(atMs: now(), flagged: status == "error"))
    }
    if span.name == "biometric.prompt" {
      let breach = duration >= MeridianTelemetryLimit.biometricPromptMs
      span.attributes["slo.metric"] = "latency"
      span.attributes["slo.threshold_ms"] = String(MeridianTelemetryLimit.biometricPromptMs)
      span.attributes["slo.breach"] = breach ? "true" : "false"
      biometricSamples.append(duration)
    }
    open.removeAll { $0 === span }
    completed.append(span)
    return span.snapshot()
  }

  public func recordSubmission(success: Bool) {
    submissions.append(TimedFlag(atMs: now(), flagged: !success))
  }

  public func recordSca(dropped: Bool, detail: String = "") {
    scaEvents.append(TimedFlag(atMs: now(), flagged: dropped))
    let clean = TelemetrySanitizer.sanitize(detail)
    let suffix = clean.isEmpty ? "" : " \(clean)"
    breadcrumbs.append(dropped ? "sca dropped\(suffix)" : "sca completed\(suffix)")
  }

  public func recordBiometricPrompt(durationMs: Int64) -> BiometricPromptResult {
    let span = startSpan(name: "biometric.prompt")
    let snapshot = endSpan(span, status: "ok", durationMs: durationMs)
    return BiometricPromptResult(durationMs: snapshot.durationMs, withinSlo: snapshot.durationMs < MeridianTelemetryLimit.biometricPromptMs)
  }

  public func measureBiometricPrompt() -> BiometricPromptResult {
    let span = startSpan(name: "biometric.prompt")
    let snapshot = endSpan(span, status: "ok")
    return BiometricPromptResult(durationMs: snapshot.durationMs, withinSlo: snapshot.durationMs < MeridianTelemetryLimit.biometricPromptMs)
  }

  public func paymentSlo() -> LatencySloReport {
    paymentSloLocked()
  }

  public func biometricSlo() -> LatencySloReport {
    biometricSloLocked()
  }

  public func evaluateAlerts() -> AlertDecision {
    evaluateLocked(atMs: now())
  }

  public func snapshot() -> TelemetrySnapshot {
    TelemetrySnapshot(
      traceId: traceId,
      spans: (open + completed).map { $0.snapshot() },
      errorLogs: errorLogs,
      breadcrumbs: breadcrumbs,
      paymentSlo: paymentSloLocked(),
      biometricSlo: biometricSloLocked(),
      alerts: evaluateLocked(atMs: now())
    )
  }

  private func paymentSloLocked() -> LatencySloReport {
    guard !paymentSamples.isEmpty else {
      return LatencySloReport(metric: "p95", thresholdMs: MeridianTelemetryLimit.paymentSubmissionP95Ms, observedMs: nil, withinSlo: true, samples: 0)
    }
    let observed = percentile95(paymentSamples)
    return LatencySloReport(
      metric: "p95",
      thresholdMs: MeridianTelemetryLimit.paymentSubmissionP95Ms,
      observedMs: observed,
      withinSlo: observed < MeridianTelemetryLimit.paymentSubmissionP95Ms,
      samples: paymentSamples.count
    )
  }

  private func biometricSloLocked() -> LatencySloReport {
    guard let observed = biometricSamples.max() else {
      return LatencySloReport(metric: "latency", thresholdMs: MeridianTelemetryLimit.biometricPromptMs, observedMs: nil, withinSlo: true, samples: 0)
    }
    return LatencySloReport(
      metric: "latency",
      thresholdMs: MeridianTelemetryLimit.biometricPromptMs,
      observedMs: observed,
      withinSlo: observed < MeridianTelemetryLimit.biometricPromptMs,
      samples: biometricSamples.count
    )
  }

  private func evaluateLocked(atMs: Int64) -> AlertDecision {
    let windowStart = atMs - MeridianTelemetryLimit.pagerWindowMs
    let recentSubmissions = submissions.filter { $0.atMs >= windowStart && $0.atMs <= atMs }
    let recentSca = scaEvents.filter { $0.atMs >= windowStart && $0.atMs <= atMs }
    let failures = recentSubmissions.filter(\.flagged).count
    let dropped = recentSca.filter(\.flagged).count
    var reasons: [String] = []
    if !recentSubmissions.isEmpty, failures * 100 > recentSubmissions.count * MeridianTelemetryLimit.submissionErrorRatePercent {
      reasons.append("submission error rate \(formatPercent(failures, recentSubmissions.count)) exceeds 1.0% over 5 minutes")
    }
    if !recentSca.isEmpty, dropped * 100 > recentSca.count * MeridianTelemetryLimit.scaDropOffPercent {
      reasons.append("SCA drop-offs \(formatPercent(dropped, recentSca.count)) exceed 5%")
    }
    return AlertDecision(
      shouldPage: !reasons.isEmpty,
      reasons: reasons,
      submissionErrorRate: recentSubmissions.isEmpty ? nil : Double(failures) / Double(recentSubmissions.count),
      scaDropOffRate: recentSca.isEmpty ? nil : Double(dropped) / Double(recentSca.count)
    )
  }
}

private func percentile95(_ values: [Int64]) -> Int64 {
  let sorted = values.sorted()
  let count = sorted.count
  let rank = (count * 95 + 99) / 100
  return sorted[min(max(rank, 1), count) - 1]
}

private func formatPercent(_ numerator: Int, _ denominator: Int) -> String {
  let scaled = denominator == 0 ? 0 : (numerator * 10_000) / denominator
  return String(format: "%d.%02d%%", scaled / 100, scaled % 100)
}

private extension TraceContext {
  func copying(tracestate: String?) -> TraceContext {
    TraceContext(traceId: traceId, spanId: spanId, sampled: sampled, tracestate: tracestate)
  }
}
