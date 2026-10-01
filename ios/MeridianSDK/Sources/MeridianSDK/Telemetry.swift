import CryptoKit
import Foundation

// MARK: - TelemetryConfig

/// Configuration for payment audit logging and distributed tracing.
///
/// - `failedJourneySampleRate`: Fraction of failed payment journeys to emit as audit log
///   entries. Range [0.0, 1.0]. 1.0 logs every failure; 0.0 suppresses all failure logs.
///   Successful journeys are always emitted regardless of this setting.
/// - `onEntry`: Receives each emitted `AuditLogEntry`. Entries never contain raw
///   credentials, bearer tokens, handoff URLs, or unhashed idempotency keys.
public struct TelemetryConfig: Sendable {
  public let failedJourneySampleRate: Double
  public let onEntry: @Sendable (AuditLogEntry) -> Void

  public init(
    failedJourneySampleRate: Double = 1.0,
    onEntry: @escaping @Sendable (AuditLogEntry) -> Void = { entry in
      fputs("[MERIDIAN_AUDIT] \(entry.toLogLine())\n", stderr)
    }
  ) {
    precondition(
      (0.0...1.0).contains(failedJourneySampleRate),
      "failedJourneySampleRate must be between 0.0 and 1.0"
    )
    self.failedJourneySampleRate = failedJourneySampleRate
    self.onEntry = onEntry
  }
}

// MARK: - TraceContext

/// W3C traceparent-compatible trace context for distributed tracing.
/// Propagated as the X-Trace-ID request header on every outbound API call
/// and included in all error reports.
public struct TraceContext: Sendable {
  /// 32 lowercase hex characters (W3C trace-id field).
  public let traceId: String
  /// 16 lowercase hex characters (W3C parent-id field).
  public let spanId: String

  /// W3C traceparent value: "00-{traceId}-{spanId}-01"
  public var traceparent: String { "00-\(traceId)-\(spanId)-01" }

  /// Generate a fresh trace context with cryptographically random IDs.
  public static func generate() -> TraceContext {
    let traceId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let spanId = String(
      UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16)
    )
    return TraceContext(traceId: traceId, spanId: spanId)
  }
}

// MARK: - AuditLogEntry

/// A single structured audit log entry for one payment journey event.
///
/// Idempotency keys are stored exclusively as SHA-256 hashes.
/// No raw credentials, bearer tokens, handoff URLs, or bank account details
/// appear in any field of this structure.
public struct AuditLogEntry: Sendable {
  /// Trace ID linking this entry to a distributed trace.
  public let traceId: String
  /// ISO-8601 UTC timestamp when this entry was produced.
  public let timestamp: String
  /// Event name: "payment.submitted" or "payment.completed".
  public let event: String
  /// Terminal outcome: "success" | "declined" | "pending" | "error". Nil if in-flight.
  public let outcome: String?
  /// SHA-256 hex digest of the raw idempotency key. The raw key is never stored.
  public let hashedIdempotencyKey: String?
  /// Days elapsed since the catalog's demoDate. Nil when catalog not yet fetched.
  public let catalogAgeDays: Int?
  /// Total payment method slots across all catalog providers.
  public let methodCount: Int?
  /// True when Strong Customer Authentication (SCA/PSD2) was invoked for this journey.
  public let scaInvoked: Bool?
  /// End-to-end API request latency in milliseconds.
  public let latencyMs: Int?
  /// Payment amount in GBP pence (integer).
  public let amountMinor: Int?
  /// Payment method: "card" or "bank".
  public let paymentMethod: String?

  public init(
    traceId: String,
    timestamp: String,
    event: String,
    outcome: String? = nil,
    hashedIdempotencyKey: String? = nil,
    catalogAgeDays: Int? = nil,
    methodCount: Int? = nil,
    scaInvoked: Bool? = nil,
    latencyMs: Int? = nil,
    amountMinor: Int? = nil,
    paymentMethod: String? = nil
  ) {
    self.traceId = traceId
    self.timestamp = timestamp
    self.event = event
    self.outcome = outcome
    self.hashedIdempotencyKey = hashedIdempotencyKey
    self.catalogAgeDays = catalogAgeDays
    self.methodCount = methodCount
    self.scaInvoked = scaInvoked
    self.latencyMs = latencyMs
    self.amountMinor = amountMinor
    self.paymentMethod = paymentMethod
  }

  /// Single-line structured log representation. Safe to write to any log sink.
  public func toLogLine() -> String {
    var parts = ["trace=\(traceId)", "ts=\(timestamp)", "event=\(event)"]
    if let v = outcome { parts.append("outcome=\(v)") }
    if let v = hashedIdempotencyKey { parts.append("idem_hash=\(v)") }
    if let v = catalogAgeDays { parts.append("catalog_age_days=\(v)") }
    if let v = methodCount { parts.append("method_count=\(v)") }
    if let v = scaInvoked { parts.append("sca=\(v)") }
    if let v = latencyMs { parts.append("latency_ms=\(v)") }
    if let v = amountMinor { parts.append("amount_pence=\(v)") }
    if let v = paymentMethod { parts.append("method=\(v)") }
    return parts.joined(separator: " ")
  }
}

// MARK: - Hash & Sanitize

/// Compute the SHA-256 hex digest of a raw idempotency key.
/// Use the returned hash for audit logging; never log the original key.
public func hashIdempotencyKey(_ rawKey: String) -> String {
  let data = Data(rawKey.utf8)
  let hash = SHA256.hash(data: data)
  return hash.compactMap { String(format: "%02x", $0) }.joined()
}

/// Sanitize a string before writing it to an audit log.
///
/// - Removes URL query parameters, which can carry OAuth tokens, session codes, or API keys.
/// - Redacts values following bearer, basic, token, apikey, secret, password, credential,
///   or auth keywords, which may contain bank credentials or provider secrets.
public func sanitizeForLog(_ input: String) -> String {
  var result = input

  // Strip URL query parameters — these can carry tokens, OAuth codes, and session secrets
  if let queryRegex = try? NSRegularExpression(pattern: #"\?[^\s#]*"#) {
    let range = NSRange(result.startIndex..., in: result)
    result = queryRegex.stringByReplacingMatches(
      in: result, range: range, withTemplate: "?[REDACTED]"
    )
  }

  // Redact auth credential patterns (keyword=value, keyword: value, or keyword value)
  if let credRegex = try? NSRegularExpression(
    pattern: #"(?i)(bearer|basic|token|apikey|api[_-]key|secret|password|credential|auth)(\s*[:=]\s*|\s+)\S+"#
  ) {
    let range = NSRange(result.startIndex..., in: result)
    result = credRegex.stringByReplacingMatches(
      in: result, range: range, withTemplate: "$1=[REDACTED]"
    )
  }

  return result
}
