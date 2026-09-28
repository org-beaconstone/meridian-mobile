import Foundation

/// In-process OpenTelemetry-compatible trace context.
/// Outbound HTTP uses the W3C `traceparent` header. Spans stay on device:
/// nothing is exported to a collector and no payment provider is contacted.
public struct TraceContext: Equatable, Sendable {
  public let traceId: String
  public let spanId: String
  public let sampled: Bool

  public var traceparent: String {
    "00-\(traceId)-\(spanId)-\(sampled ? "01" : "00")"
  }

  public static func root() -> TraceContext {
    TraceContext(traceId: TraceIds.hex(byteCount: 16), spanId: TraceIds.hex(byteCount: 8), sampled: true)
  }

  public func child() -> TraceContext {
    TraceContext(traceId: traceId, spanId: TraceIds.hex(byteCount: 8), sampled: sampled)
  }

  public static func isValidTraceparent(_ value: String) -> Bool {
    let parts = value.split(separator: "-")
    guard parts.count == 4 else { return false }
    let version = String(parts[0])
    let trace = String(parts[1])
    let span = String(parts[2])
    let flags = String(parts[3])
    guard version == "00", flags.count == 2 else { return false }
    guard trace.count == 32, span.count == 16 else { return false }
    guard trace != String(repeating: "0", count: 32) else { return false }
    guard span != String(repeating: "0", count: 16) else { return false }
    let hex = CharacterSet(charactersIn: "0123456789abcdef")
    func isLowerHex(_ text: String) -> Bool {
      text.unicodeScalars.allSatisfy { hex.contains($0) }
    }
    return isLowerHex(trace) && isLowerHex(span) && isLowerHex(flags)
  }
}

enum TraceIds {
  static func hex(byteCount: Int) -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    repeat {
      for index in 0..<byteCount {
        bytes[index] = UInt8.random(in: 0...255)
      }
    } while bytes.allSatisfy { $0 == 0 }
    return bytes.map { String(format: "%02x", $0) }.joined()
  }
}

public struct SpanRecord: Equatable, Sendable {
  public let name: String
  public let traceId: String
  public let spanId: String
  public let parentSpanId: String?
  public let durationMillis: Int64
  public let status: String
  public let attributes: [String: String]
}

public struct TelemetryEvent: Equatable, Sendable {
  public let name: String
  public let errorCode: String
  public let failureStage: String
  public let attributes: [String: String]
}

public struct CorridorHealth: Equatable, Sendable {
  public let id: String
  public let state: String
  public let provider: String?
  public let method: String?
}

public struct SessionHealthReport: Equatable, Sendable {
  public let connectionState: String
  public let httpStatus: Int?
  public let corridors: [CorridorHealth]
}

public struct BiometricResolution: Equatable, Sendable {
  public let accepted: Bool
  public let fallback: Bool
  public let durationMillis: Int64
}

enum MonotonicMark {
  static func millis(since start: ContinuousClock.Instant) -> Int64 {
    let parts = start.duration(to: ContinuousClock().now).components
    let value = parts.seconds * 1_000 + parts.attoseconds / 1_000_000_000_000_000
    return value < 0 ? 0 : value
  }
}

public enum TelemetrySanitizer {
  private static let ibanCompact = try? NSRegularExpression(
    pattern: "(?<![A-Za-z0-9])[A-Za-z]{2}[0-9]{2}[A-Za-z0-9]{11,30}(?![A-Za-z0-9])",
    options: [.caseInsensitive]
  )
  private static let ibanGrouped = try? NSRegularExpression(
    pattern: "(?<![A-Za-z0-9])[A-Za-z]{2}[0-9]{2}(?:[ -][A-Za-z0-9]{4}){2,7}(?:[ -][A-Za-z0-9]{1,3})?(?![A-Za-z0-9])",
    options: [.caseInsensitive]
  )
  private static let pan = try? NSRegularExpression(
    pattern: "(?<![0-9])(?:[0-9][ -]?){12,18}[0-9](?![0-9])",
    options: []
  )

  public static func redact(_ input: String) -> String {
    var text = replace(ibanGrouped, in: input, with: "[REDACTED_IBAN]")
    text = replace(ibanCompact, in: text, with: "[REDACTED_IBAN]")
    text = replace(pan, in: text, with: "[REDACTED_PAN]")
    return text
  }

  public static func containsSensitive(_ input: String) -> Bool {
    redact(input) != input
  }

  private static func replace(_ regex: NSRegularExpression?, in text: String, with template: String) -> String {
    guard let regex else { return text }
    let range = NSRange(text.startIndex..., in: text)
    return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
  }
}

public func shouldInjectTraceparent(path: String) -> Bool {
  let bare = path.split(separator: "?").first.map(String.init) ?? path
  let trimmed = bare.hasSuffix("/") && bare.count > 1 ? String(bare.dropLast()) : bare
  return trimmed.hasSuffix("/catalog") || trimmed.hasSuffix("/payments") || trimmed.hasSuffix("/session/health")
}

enum SessionHealthParser {
  static func parse(statusCode: Int, data: Data) -> SessionHealthReport {
    if statusCode == 0 {
      return SessionHealthReport(connectionState: "unreachable", httpStatus: nil, corridors: [])
    }
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    let status = (json?["status"] as? String)?.lowercased() ?? ""
    var corridors: [CorridorHealth] = []
    if let rows = json?["corridors"] as? [[String: Any]] {
      for row in rows {
        if let corridor = normalize(
          id: row["id"] as? String,
          provider: row["provider"] as? String,
          method: row["method"] as? String,
          state: row["state"] as? String
        ) {
          corridors.append(corridor)
        }
      }
    }
    let connection = connectionState(status: status, httpStatus: statusCode, corridors: corridors)
    return SessionHealthReport(connectionState: connection, httpStatus: statusCode, corridors: corridors)
  }

  private static func connectionState(status: String, httpStatus: Int, corridors: [CorridorHealth]) -> String {
    if httpStatus >= 500 || httpStatus == 0 { return "unreachable" }
    if corridors.contains(where: { $0.state == "down" }) { return "unreachable" }
    if corridors.contains(where: { $0.state == "degraded" }) { return "degraded" }
    switch status {
    case "up", "ok", "healthy":
      return httpStatus >= 400 ? "degraded" : "healthy"
    case "degraded", "warn", "warning":
      return "degraded"
    case "down", "unavailable", "unreachable":
      return "unreachable"
    default:
      return httpStatus >= 400 ? "degraded" : "degraded"
    }
  }

  private static func normalize(id: String?, provider: String?, method: String?, state: String?) -> CorridorHealth? {
    let normalizedState: String
    switch (state ?? "").lowercased() {
    case "ok", "up", "healthy":
      normalizedState = "healthy"
    case "degraded", "warn", "warning":
      normalizedState = "degraded"
    case "down", "unavailable", "unreachable":
      normalizedState = "down"
    default:
      return nil
    }
    let providerName = provider?.lowercased()
    let methodName = method?.lowercased()
    let corridorId = id?.lowercased()
    let mapped: (String, String, String)?
    if providerName == "adyen", methodName == nil || methodName == "card" {
      mapped = ("adyen-card", "adyen", "card")
    } else if providerName == "worldpay", methodName == nil || methodName == "bank" {
      mapped = ("worldpay-bank", "worldpay", "bank")
    } else if corridorId == "adyen-card" {
      mapped = ("adyen-card", "adyen", "card")
    } else if corridorId == "worldpay-bank" {
      mapped = ("worldpay-bank", "worldpay", "bank")
    } else {
      mapped = nil
    }
    if let mapped {
      return CorridorHealth(id: mapped.0, state: normalizedState, provider: mapped.1, method: mapped.2)
    }
    if normalizedState == "healthy" { return nil }
    return CorridorHealth(id: "session", state: normalizedState, provider: nil, method: nil)
  }
}

public final class TelemetryLog: @unchecked Sendable {
  private let lock = NSLock()
  private var spanList: [SpanRecord] = []
  private var eventList: [TelemetryEvent] = []
  private var connection = "unknown"
  private var corridorStates: [String: String] = [:]

  public init() {}

  public func spans() -> [SpanRecord] {
    lock.lock()
    defer { lock.unlock() }
    return spanList
  }

  public func events() -> [TelemetryEvent] {
    lock.lock()
    defer { lock.unlock() }
    return eventList
  }

  public func connectionState() -> String {
    lock.lock()
    defer { lock.unlock() }
    return connection
  }

  public func rendered() -> String {
    lock.lock()
    defer { lock.unlock() }
    let spanText = spanList.map { span in
      "span \(span.name) \(span.status) \(span.attributes.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: ","))"
    }.joined(separator: "\n")
    let eventText = eventList.map { event in
      "event \(event.name) \(event.errorCode) \(event.failureStage) \(event.attributes.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: ","))"
    }.joined(separator: "\n")
    return spanText + "\n" + eventText
  }

  func recordSpan(
    name: String,
    context: TraceContext,
    parentSpanId: String?,
    durationMillis: Int64,
    status: String,
    attributes: [String: String]
  ) {
    let record = SpanRecord(
      name: name,
      traceId: context.traceId,
      spanId: context.spanId,
      parentSpanId: parentSpanId,
      durationMillis: max(0, durationMillis),
      status: status,
      attributes: AttributePolicy.sanitize(attributes)
    )
    lock.lock()
    spanList.append(record)
    lock.unlock()
  }

  func recordError(code: String, stage: String, attributes: [String: String] = [:]) {
    recordEvent(name: "client.error", code: code, stage: stage, attributes: attributes)
  }

  func recordEvent(name: String, code: String, stage: String, attributes: [String: String] = [:]) {
    let event = TelemetryEvent(
      name: name,
      errorCode: AttributePolicy.safeCode(code),
      failureStage: AttributePolicy.safeStage(stage),
      attributes: AttributePolicy.sanitize(attributes)
    )
    lock.lock()
    eventList.append(event)
    lock.unlock()
  }

  func observeSessionHealth(_ report: SessionHealthReport, durationMillis: Int64) {
    lock.lock()
    let previous = connection
    var emittedCorridor = false
    if previous != report.connectionState {
      connection = report.connectionState
      eventList.append(
        TelemetryEvent(
          name: "session.connection_changed",
          errorCode: report.httpStatus.map { "HTTP_\($0)" } ?? "NONE",
          failureStage: "session_health",
          attributes: AttributePolicy.sanitize([
            "connection.previous": previous,
            "connection.current": report.connectionState,
            "http.status_code": report.httpStatus.map(String.init) ?? "",
            "duration_ms": String(max(0, durationMillis)),
          ])
        )
      )
    }
    for corridor in report.corridors {
      let prior = corridorStates[corridor.id] ?? "unknown"
      if prior == corridor.state { continue }
      corridorStates[corridor.id] = corridor.state
      if corridor.state == "degraded" || corridor.state == "down" {
        emittedCorridor = true
        var attributes = [
          "corridor.id": corridor.id,
          "corridor.state": corridor.state,
          "connection.previous": prior,
          "connection.current": corridor.state,
        ]
        if let provider = corridor.provider { attributes["payment.provider"] = provider }
        if let method = corridor.method { attributes["payment.method"] = method }
        eventList.append(
          TelemetryEvent(
            name: "corridor.degraded",
            errorCode: "CORRIDOR_\(corridor.state.uppercased())",
            failureStage: "session_health",
            attributes: AttributePolicy.sanitize(attributes)
          )
        )
      }
    }
    let worsened = report.connectionState == "degraded" || report.connectionState == "unreachable"
    if worsened && previous != report.connectionState && !emittedCorridor && report.corridors.isEmpty {
      eventList.append(
        TelemetryEvent(
          name: "corridor.degraded",
          errorCode: "CORRIDOR_\(report.connectionState.uppercased())",
          failureStage: "session_health",
          attributes: AttributePolicy.sanitize([
            "corridor.id": "session",
            "corridor.state": report.connectionState == "unreachable" ? "down" : "degraded",
            "connection.previous": previous,
            "connection.current": report.connectionState,
          ])
        )
      )
    }
    lock.unlock()
  }
}

enum AttributePolicy {
  private static let allowed: Set<String> = [
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
  ]

  static func sanitize(_ input: [String: String]) -> [String: String] {
    var output: [String: String] = [:]
    for (key, value) in input where allowed.contains(key) {
      let cleaned = clean(key: key, value: value)
      if !cleaned.isEmpty {
        output[key] = cleaned
      }
    }
    return output
  }

  static func safeCode(_ code: String) -> String {
    let token = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard token.range(of: "^[A-Za-z0-9_]{1,64}$", options: .regularExpression) != nil else {
      return "REDACTED_CODE"
    }
    return TelemetrySanitizer.containsSensitive(token) ? "REDACTED_CODE" : token
  }

  static func safeStage(_ stage: String) -> String {
    let token = stage.trimmingCharacters(in: .whitespacesAndNewlines)
    guard token.range(of: "^[a-z0-9_]{1,64}$", options: .regularExpression) != nil else {
      return "unknown"
    }
    return token
  }

  private static func clean(key: String, value: String) -> String {
    switch key {
    case "payment.provider":
      return value == "adyen" || value == "worldpay" ? value : ""
    case "payment.method":
      return value == "card" || value == "bank" ? value : ""
    case "http.status_code", "recipient.count", "provider.count", "duration_ms":
      return value.range(of: "^[0-9]{1,12}$", options: .regularExpression) != nil ? value : ""
    case "http.method":
      return value.range(of: "^[A-Z]{1,8}$", options: .regularExpression) != nil ? value : ""
    case "error.message":
      return String(TelemetrySanitizer.redact(value).prefix(180))
    case "corridor.id":
      return value == "adyen-card" || value == "worldpay-bank" || value == "session" ? value : ""
    case "corridor.state", "connection.previous", "connection.current":
      let redacted = TelemetrySanitizer.redact(value)
      return redacted.range(of: "^[a-z0-9_.:-]{1,64}$", options: .regularExpression) != nil ? redacted : ""
    case "outcome":
      let redacted = TelemetrySanitizer.redact(value)
      guard redacted.range(of: "^[A-Za-z0-9_.:-]{1,64}$", options: .regularExpression) != nil else {
        return ""
      }
      return TelemetrySanitizer.containsSensitive(redacted) ? "" : redacted
    default:
      let redacted = TelemetrySanitizer.redact(value)
      return redacted.count <= 80 ? redacted : String(redacted.prefix(80))
    }
  }
}
