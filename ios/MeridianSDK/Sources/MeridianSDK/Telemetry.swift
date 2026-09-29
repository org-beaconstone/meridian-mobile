import Foundation

/// In-process W3C Trace Context and structured telemetry.
/// Spans stay on the device. Nothing is exported to a collector, and no provider network call is made.
public final class TelemetryLog: @unchecked Sendable {
  private let lock = NSLock()
  private var spanRecords: [SpanRecord] = []
  private var eventRecords: [TelemetryEvent] = []

  public init() {}

  public func startSpan(
    name: String,
    traceId: String = TraceIds.hex(16),
    parentSpanId: String? = nil
  ) -> SpanToken {
    SpanToken(
      name: name,
      traceId: traceId,
      spanId: TraceIds.hex(8),
      parentSpanId: parentSpanId,
      started: Date()
    )
  }

  public func endSpan(_ token: SpanToken, status: String, attributes: [String: String] = [:]) {
    let millis = max(0, Int((Date().timeIntervalSince(token.started) * 1000.0).rounded()))
    let record = SpanRecord(
      name: token.name,
      traceId: token.traceId,
      spanId: token.spanId,
      parentSpanId: token.parentSpanId,
      durationMillis: millis,
      status: status,
      attributes: Sanitizer.cleanAttributes(attributes)
    )
    lock.lock()
    spanRecords.append(record)
    lock.unlock()
  }

  public func recordError(
    code: String,
    stage: String,
    message: String,
    traceId: String,
    spanId: String,
    attributes: [String: String] = [:]
  ) {
    record(
      TelemetryEvent(
        name: "client.error",
        code: String(Sanitizer.sanitize(code).prefix(80)),
        stage: stage,
        message: String(Sanitizer.sanitize(message).prefix(180)),
        traceId: traceId,
        spanId: spanId,
        attributes: Sanitizer.cleanAttributes(attributes)
      )
    )
  }

  public func record(_ event: TelemetryEvent) {
    let safe = TelemetryEvent(
      name: event.name,
      code: String(Sanitizer.sanitize(event.code).prefix(80)),
      stage: event.stage,
      message: String(Sanitizer.sanitize(event.message).prefix(180)),
      traceId: event.traceId,
      spanId: event.spanId,
      attributes: Sanitizer.cleanAttributes(event.attributes)
    )
    lock.lock()
    eventRecords.append(safe)
    lock.unlock()
  }

  public func spans() -> [SpanRecord] {
    lock.lock()
    defer { lock.unlock() }
    return spanRecords
  }

  public func events() -> [TelemetryEvent] {
    lock.lock()
    defer { lock.unlock() }
    return eventRecords
  }
}

public struct SpanToken: Sendable {
  public let name: String
  public let traceId: String
  public let spanId: String
  public let parentSpanId: String?
  let started: Date

  public var traceparent: String { TraceIds.traceparent(traceId: traceId, spanId: spanId) }
}

public struct SpanRecord: Equatable, Sendable {
  public let name: String
  public let traceId: String
  public let spanId: String
  public let parentSpanId: String?
  public let durationMillis: Int
  public let status: String
  public let attributes: [String: String]
}

public struct TelemetryEvent: Equatable, Sendable {
  public let name: String
  public let code: String
  public let stage: String
  public let message: String
  public let traceId: String
  public let spanId: String
  public let attributes: [String: String]
}

public struct BiometricResolution: Equatable, Sendable {
  public let outcome: String
  public let code: String?
}

public struct CorridorStatus: Equatable, Sendable {
  public let id: String
  public let state: String
}

public struct SessionHealthSnapshot: Equatable, Sendable {
  public let connection: String
  public let corridors: [CorridorStatus]

  public var summary: String {
    let degraded = corridors.filter { $0.state == "degraded" || $0.state == "down" }
    if degraded.isEmpty {
      return "Session health: \(connection)"
    }
    let detail = degraded.map { "\($0.id) \($0.state)" }.joined(separator: ", ")
    return "Session health: \(connection) · \(detail)"
  }
}

public enum TraceIds {
  public static func hex(_ numBytes: Int) -> String {
    let alphabet = Array("0123456789abcdef")
    for _ in 0..<4 {
      var bytes = [UInt8](repeating: 0, count: numBytes)
      for index in bytes.indices {
        bytes[index] = UInt8.random(in: 0...255)
      }
      var encoded = ""
      encoded.reserveCapacity(numBytes * 2)
      for byte in bytes {
        encoded.append(alphabet[Int(byte >> 4)])
        encoded.append(alphabet[Int(byte & 0x0f)])
      }
      if encoded.contains(where: { $0 != "0" }) {
        return encoded
      }
    }
    return String(repeating: "0", count: numBytes * 2 - 1) + "1"
  }

  public static func traceparent(traceId: String, spanId: String) -> String {
    "00-\(traceId)-\(spanId)-01"
  }

  public static func isTraceparent(_ value: String) -> Bool {
    let pattern = "^00-[0-9a-f]{32}-[0-9a-f]{16}-01$"
    return value.range(of: pattern, options: .regularExpression) != nil
  }
}

public enum Sanitizer {
  public static func sanitize(_ input: String) -> String {
    if input.isEmpty { return input }
    return replace(scrubIbans(input), pattern: #"(?<![0-9])(?:\d[ -]?){12,18}\d(?![0-9])"#) { match in
      let digits = match.filter(\.isNumber)
      return (digits.count >= 13 && digits.count <= 19 && luhn(digits)) ? "[REDACTED_PAN]" : match
    }
  }

  private static func scrubIbans(_ input: String) -> String {
    guard let prefix = try? NSRegularExpression(pattern: #"(?i)(?<![A-Za-z0-9])[A-Z]{2}\d{2}"#) else { return input }
    let nsInput = input as NSString
    var result = ""
    var index = 0
    while index < input.count {
      let search = NSRange(location: index, length: input.count - index)
      guard let match = prefix.firstMatch(in: input, range: search) else { break }
      let start = match.range.location
      result += nsInput.substring(with: NSRange(location: index, length: start - index))
      var cursor = start + match.range.length
      var accepted = -1
      while cursor <= input.count {
        let candidate = nsInput.substring(with: NSRange(location: start, length: cursor - start))
        let compactLength = candidate.filter { !$0.isWhitespace }.count
        if compactLength >= 15 && isIban(candidate) { accepted = cursor }
        if cursor == input.count || compactLength >= 34 { break }
        let nextIndex = input.index(input.startIndex, offsetBy: cursor)
        let next = input[nextIndex]
        if next == " " {
          let following = input.index(after: nextIndex)
          if following < input.endIndex && input[following].isLetter || (following < input.endIndex && input[following].isNumber) {
            cursor += 1
            continue
          }
          break
        }
        if !next.isLetter && !next.isNumber { break }
        cursor += 1
      }
      if accepted > start {
        result += "[REDACTED_IBAN]"
        index = accepted
      } else {
        result += nsInput.substring(with: match.range)
        index = start + match.range.length
      }
    }
    if index < input.count {
      result += nsInput.substring(from: index)
    }
    return result
  }

  public static func cleanAttributes(_ input: [String: String]) -> [String: String] {
    var cleaned: [String: String] = [:]
    let forbidden: Set<String> = [
      "pan", "iban", "card", "cardnumber", "accountnumber", "cvv", "cvc", "note", "detail", "recipientdetail",
    ]
    for (key, value) in input {
      let normalized = key.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
      if forbidden.contains(normalized) || normalized.contains("pan") || normalized.contains("iban") {
        continue
      }
      cleaned[key] = String(sanitize(value).prefix(180))
    }
    return cleaned
  }

  public static func isIban(_ candidate: String) -> Bool {
    let compact = candidate.replacingOccurrences(of: " ", with: "").uppercased()
    guard (15...34).contains(compact.count) else { return false }
    guard compact.range(of: #"^[A-Z]{2}[0-9]{2}[A-Z0-9]+$"#, options: .regularExpression) != nil else { return false }
    let rearranged = String(compact.dropFirst(4)) + String(compact.prefix(4))
    var numeric = ""
    for character in rearranged {
      if character.isNumber {
        numeric.append(character)
      } else if let ascii = character.asciiValue, character.isLetter {
        numeric.append(String(Int(ascii) - 55))
      } else {
        return false
      }
    }
    return mod97(numeric) == 1
  }

  public static func luhn(_ digits: String) -> Bool {
    guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return false }
    var sum = 0
    var alternate = false
    for character in digits.reversed() {
      guard var current = character.wholeNumberValue else { return false }
      if alternate {
        current *= 2
        if current > 9 { current -= 9 }
      }
      sum += current
      alternate.toggle()
    }
    return sum % 10 == 0
  }

  private static func mod97(_ numeric: String) -> Int {
    var remainder = 0
    for character in numeric {
      guard let digit = character.wholeNumberValue else { return -1 }
      remainder = (remainder * 10 + digit) % 97
    }
    return remainder
  }

  private static func replace(_ input: String, pattern: String, transform: (String) -> String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
    let range = NSRange(input.startIndex..<input.endIndex, in: input)
    var result = input
    let matches = regex.matches(in: result, range: range).reversed()
    for match in matches {
      guard let matchRange = Range(match.range, in: result) else { continue }
      let original = String(result[matchRange])
      result.replaceSubrange(matchRange, with: transform(original))
    }
    return result
  }
}

public enum CorridorIds {
  private static let cardIds: Set<String> = ["adyen", "card", "adyen-card"]
  private static let bankIds: Set<String> = ["worldpay", "bank", "worldpay-bank"]

  public static func canonical(id: String?, provider: String?) -> String {
    let candidates = [id, provider]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
      .filter { !$0.isEmpty }
    if candidates.contains(where: { bankIds.contains($0) }) { return "worldpay-bank" }
    if candidates.contains(where: { cardIds.contains($0) }) { return "adyen-card" }
    return "corridor"
  }

  public static func state(_ state: String?, status: String?) -> String {
    let raw = (state ?? status ?? "unknown").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch raw {
    case "healthy", "ok", "up": return "healthy"
    case "degraded", "impaired": return "degraded"
    case "down", "unavailable", "failed": return "down"
    default: return "unknown"
    }
  }

  public static func connection(explicit: String?, status: String?, corridors: [CorridorStatus]) -> String {
    let normalized = explicit?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let degraded = corridors.contains { $0.state == "degraded" || $0.state == "down" }
    if normalized == "disconnected" || normalized == "down" { return "disconnected" }
    if normalized == "degraded" || degraded { return "degraded" }
    if normalized == "connected" || normalized == "up" { return "connected" }
    switch status?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
    case "DOWN", "UNAVAILABLE": return "disconnected"
    default: return "connected"
    }
  }
}
