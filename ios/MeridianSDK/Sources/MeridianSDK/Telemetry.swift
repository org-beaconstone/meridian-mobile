import CryptoKit
import Foundation

// MARK: - Trace Context (W3C Trace Context §3.2)

/// Holds a W3C-compatible distributed trace identifier for one client session.
public struct TraceContext: Sendable {
    /// 128-bit trace identifier as 32 lowercase hex characters.
    public let traceId: String

    public init() {
        self.traceId = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    /// Builds a `traceparent` header value for a single outgoing request span.
    /// - Parameter spanId: 16 lowercase hex characters identifying this span.
    public func traceparent(spanId: String) -> String {
        "00-\(traceId)-\(spanId)-01"
    }

    /// Generates a fresh 64-bit span identifier (16 lowercase hex characters).
    public static func newSpanId() -> String {
        String(
            UUID().uuidString
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
                .prefix(16)
        )
    }
}

// MARK: - Payment Outcome

/// Terminal outcome of a payment journey.
public enum PaymentOutcome: String, Sendable {
    case success
    case declined
    case pending
    case error
}

// MARK: - Payment Journey Event

/// Telemetry emitted at the conclusion of a payment journey.
public struct PaymentJourneyEvent: Sendable {
    /// Session trace identifier propagated through the request chain.
    public let traceId: String
    /// Age of the last fetched catalog in seconds; nil if the catalog was never fetched.
    public let catalogAgeSeconds: Double?
    /// Total number of payment methods advertised by the catalog.
    public let methodCount: Int?
    /// Whether Strong Customer Authentication applies (true for card payments via Adyen).
    public let scaInvoked: Bool
    /// Round-trip latency of the payment network request in milliseconds.
    public let latencyMs: Int
    /// Terminal outcome of the payment journey.
    public let outcome: PaymentOutcome
    /// ISO 8601 UTC timestamp of the event.
    public let timestamp: String
}

// MARK: - Audit Log Entry

/// A sanitised audit record for a single payment attempt.
/// No raw credentials, tokens, or URLs are stored.
public struct AuditLogEntry: Sendable {
    /// Session trace identifier.
    public let traceId: String
    /// ISO 8601 UTC timestamp.
    public let timestamp: String
    /// Action label, e.g. `"PAYMENT_SUBMITTED"` or `"PAYMENT_ERROR"`.
    public let action: String
    /// SHA-256 hex digest of the raw idempotency key.
    public let hashedIdempotencyKey: String
    /// `demoDate` from the catalog response, used for catalog-version correlation.
    public let catalogVersion: String?
    /// Payment method name (`"card"` or `"bank"`); no provider credentials included.
    public let paymentMethod: String
    /// Terminal outcome string.
    public let outcome: String
}

// MARK: - Telemetry Configuration

/// Configuration for payment telemetry and audit logging.
public struct TelemetryConfig: Sendable {
    /// Fraction of failed journeys to emit as audit entries: `0.0` = none, `1.0` = all.
    /// Successful journeys are always audited regardless of this rate.
    public let failedJourneySamplingRate: Double

    /// Called with a telemetry event at the conclusion of every payment attempt.
    public let onEvent: (@Sendable (PaymentJourneyEvent) -> Void)?

    /// Called with an audit log entry for every sampled payment attempt.
    public let onAudit: (@Sendable (AuditLogEntry) -> Void)?

    public init(
        failedJourneySamplingRate: Double = 1.0,
        onEvent: (@Sendable (PaymentJourneyEvent) -> Void)? = nil,
        onAudit: (@Sendable (AuditLogEntry) -> Void)? = nil
    ) {
        precondition(
            failedJourneySamplingRate >= 0 && failedJourneySamplingRate <= 1,
            "failedJourneySamplingRate must be in [0.0, 1.0]"
        )
        self.failedJourneySamplingRate = failedJourneySamplingRate
        self.onEvent = onEvent
        self.onAudit = onAudit
    }
}

// MARK: - Internal Helpers

/// Returns the SHA-256 hex digest of a UTF-8 string.
public func sha256Hex(_ input: String) -> String {
    let digest = SHA256.hash(data: Data(input.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

/// Redacts URLs, bearer tokens, UK sort codes, and 8-digit account numbers from a string.
public func sanitizeForAudit(_ input: String) -> String {
    var s = input
    s = s.replacingOccurrences(
        of: #"https?://\S+"#, with: "[URL]",
        options: .regularExpression)
    s = s.replacingOccurrences(
        of: #"(?i)Bearer\s+[A-Za-z0-9\-._~+/]+=*"#, with: "Bearer [REDACTED]",
        options: .regularExpression)
    s = s.replacingOccurrences(
        of: #"\b\d{2}-\d{2}-\d{2}\b"#, with: "[SORT-CODE]",
        options: .regularExpression)
    s = s.replacingOccurrences(
        of: #"\b\d{8}\b"#, with: "[ACCOUNT]",
        options: .regularExpression)
    return s
}

/// Returns an ISO 8601 UTC timestamp for the current instant.
func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}
