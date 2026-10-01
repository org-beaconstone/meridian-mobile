package com.atlassian.meridian

import java.security.MessageDigest
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.UUID

// MARK: - Trace Context (W3C Trace Context §3.2)

/**
 * Holds a W3C-compatible distributed trace identifier for one client session.
 */
data class TraceContext(
    /** 128-bit trace identifier as 32 lowercase hex characters. */
    val traceId: String = generateTraceId(),
) {
    /** Builds a `traceparent` header value for a single outgoing request span. */
    fun traceparent(spanId: String): String = "00-$traceId-$spanId-01"

    companion object {
        /** Generates a 128-bit trace ID (32 lowercase hex characters). */
        fun generateTraceId(): String =
            UUID.randomUUID().toString().replace("-", "").lowercase()

        /** Generates a fresh 64-bit span ID (16 lowercase hex characters). */
        fun newSpanId(): String =
            UUID.randomUUID().toString().replace("-", "").lowercase().take(16)
    }
}

// MARK: - Payment Outcome

/** Terminal outcome of a payment journey. */
enum class PaymentOutcome {
    SUCCESS, DECLINED, PENDING, ERROR
}

// MARK: - Payment Journey Event

/**
 * Telemetry emitted at the conclusion of a payment journey.
 */
data class PaymentJourneyEvent(
    /** Session trace identifier propagated through the request chain. */
    val traceId: String,
    /** Age of the last fetched catalog in seconds; null if catalog was never fetched. */
    val catalogAgeSeconds: Double?,
    /** Total number of payment methods advertised by the catalog. */
    val methodCount: Int?,
    /** Whether Strong Customer Authentication applies (true for card payments via Adyen). */
    val scaInvoked: Boolean,
    /** Round-trip latency of the payment network request in milliseconds. */
    val latencyMs: Long,
    /** Terminal outcome of the payment journey. */
    val outcome: PaymentOutcome,
    /** ISO 8601 UTC timestamp of the event. */
    val timestamp: String,
)

// MARK: - Audit Log Entry

/**
 * A sanitised audit record for a single payment attempt.
 * No raw credentials, tokens, or URLs are stored.
 */
data class AuditLogEntry(
    /** Session trace identifier. */
    val traceId: String,
    /** ISO 8601 UTC timestamp. */
    val timestamp: String,
    /** Action label, e.g. "PAYMENT_SUBMITTED" or "PAYMENT_ERROR". */
    val action: String,
    /** SHA-256 hex digest of the raw idempotency key. */
    val hashedIdempotencyKey: String,
    /** demoDate from the catalog response, used for catalog-version correlation. */
    val catalogVersion: String?,
    /** Payment method name ("card" or "bank"); no provider credentials included. */
    val paymentMethod: String,
    /** Terminal outcome string. */
    val outcome: String,
)

// MARK: - Telemetry Configuration

/**
 * Configuration for payment telemetry and audit logging.
 */
data class TelemetryConfig(
    /**
     * Fraction of failed journeys to emit as audit entries: 0.0 = none, 1.0 = all.
     * Successful journeys are always audited regardless of this rate.
     */
    val failedJourneySamplingRate: Double = 1.0,
    /** Called with a telemetry event at the conclusion of every payment attempt. */
    val onEvent: ((PaymentJourneyEvent) -> Unit)? = null,
    /** Called with an audit log entry for every sampled payment attempt. */
    val onAudit: ((AuditLogEntry) -> Unit)? = null,
) {
    init {
        require(failedJourneySamplingRate in 0.0..1.0) {
            "failedJourneySamplingRate must be in [0.0, 1.0]"
        }
    }
}

// MARK: - Internal Helpers

/** Returns the SHA-256 hex digest of a UTF-8 string. */
fun sha256Hex(input: String): String {
    val digest = MessageDigest.getInstance("SHA-256")
    val bytes = digest.digest(input.toByteArray(Charsets.UTF_8))
    return bytes.joinToString("") { "%02x".format(it) }
}

/**
 * Redacts URLs, bearer tokens, UK sort codes, and 8-digit account numbers from a string.
 */
fun sanitizeForAudit(input: String): String {
    var s = input
    s = s.replace(Regex("""https?://\S+"""), "[URL]")
    s = s.replace(Regex("""(?i)Bearer\s+[A-Za-z0-9\-._~+/]+=*"""), "Bearer [REDACTED]")
    s = s.replace(Regex("""\b\d{2}-\d{2}-\d{2}\b"""), "[SORT-CODE]")
    s = s.replace(Regex("""\b\d{8}\b"""), "[ACCOUNT]")
    return s
}

/** Returns an ISO 8601 UTC timestamp for the current instant. */
fun isoNow(): String = DateTimeFormatter.ISO_INSTANT.format(Instant.now())
