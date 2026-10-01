package com.atlassian.meridian

import java.security.MessageDigest
import java.util.UUID

/**
 * Configuration for payment audit logging and distributed tracing.
 *
 * @param failedJourneySampleRate Fraction of failed payment journeys to emit as audit log
 *   entries. Range [0.0, 1.0]. 1.0 logs every failure; 0.0 suppresses all failure logs.
 *   Successful journeys are always emitted regardless of this setting.
 * @param onEntry Receiver for each emitted [AuditLogEntry]. Entries never contain raw
 *   credentials, bearer tokens, handoff URLs, or unhashed idempotency keys.
 */
data class TelemetryConfig(
    val failedJourneySampleRate: Double = 1.0,
    val onEntry: (AuditLogEntry) -> Unit = { entry ->
        System.err.println("[MERIDIAN_AUDIT] ${entry.toLogLine()}")
    },
) {
    init {
        require(failedJourneySampleRate in 0.0..1.0) {
            "failedJourneySampleRate must be between 0.0 and 1.0"
        }
    }
}

/**
 * W3C traceparent-compatible trace context for distributed tracing.
 * Propagated as the X-Trace-ID request header on every outbound API call
 * and included in all error reports.
 */
data class TraceContext(
    val traceId: String,  // 32 lowercase hex chars (W3C trace-id)
    val spanId: String,   // 16 lowercase hex chars (W3C parent-id)
) {
    /** W3C traceparent value: "00-{traceId}-{spanId}-01" */
    val traceparent: String get() = "00-$traceId-$spanId-01"

    companion object {
        /** Generate a fresh trace context with cryptographically random IDs. */
        fun generate(): TraceContext = TraceContext(
            traceId = UUID.randomUUID().toString().replace("-", ""),          // 32 hex chars
            spanId = UUID.randomUUID().toString().replace("-", "").take(16),  // 16 hex chars
        )
    }
}

/**
 * A single structured audit log entry for one payment journey event.
 *
 * Idempotency keys are stored exclusively as SHA-256 hashes.
 * No raw credentials, bearer tokens, handoff URLs, or bank account details
 * appear in any field of this structure.
 */
data class AuditLogEntry(
    /** Trace ID linking this entry to a distributed trace. */
    val traceId: String,
    /** ISO-8601 UTC timestamp when this entry was produced. */
    val timestamp: String,
    /** Event name: "payment.submitted" or "payment.completed". */
    val event: String,
    /** Terminal outcome: "success" | "declined" | "pending" | "error". Null if in-flight. */
    val outcome: String? = null,
    /** SHA-256 hex digest of the raw idempotency key. The raw key is never stored here. */
    val hashedIdempotencyKey: String? = null,
    /** Days elapsed since the catalog's demoDate. Null when catalog not yet fetched. */
    val catalogAgeDays: Long? = null,
    /** Total payment method slots across all catalog providers. */
    val methodCount: Int? = null,
    /** True when Strong Customer Authentication (SCA/PSD2) was invoked for this journey. */
    val scaInvoked: Boolean? = null,
    /** End-to-end API request latency in milliseconds. */
    val latencyMs: Long? = null,
    /** Payment amount in GBP pence (integer). */
    val amountMinor: Int? = null,
    /** Payment method: "card" or "bank". */
    val paymentMethod: String? = null,
) {
    /**
     * Produce a single-line structured log representation.
     * Only non-null fields are included. Safe to write to any log sink.
     */
    fun toLogLine(): String = buildString {
        append("trace=$traceId")
        append(" ts=$timestamp")
        append(" event=$event")
        outcome?.let { append(" outcome=$it") }
        hashedIdempotencyKey?.let { append(" idem_hash=$it") }
        catalogAgeDays?.let { append(" catalog_age_days=$it") }
        methodCount?.let { append(" method_count=$it") }
        scaInvoked?.let { append(" sca=$it") }
        latencyMs?.let { append(" latency_ms=$it") }
        amountMinor?.let { append(" amount_pence=$it") }
        paymentMethod?.let { append(" method=$it") }
    }
}

/**
 * Compute the SHA-256 hex digest of a raw idempotency key.
 * Use the returned hash for audit logging; never log the original key.
 */
fun hashIdempotencyKey(rawKey: String): String {
    val digest = MessageDigest.getInstance("SHA-256")
    return digest.digest(rawKey.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
}

/**
 * Sanitize a string before writing it to an audit log.
 *
 * - Removes URL query parameters, which can carry OAuth tokens, session codes, or API keys.
 * - Redacts values following bearer, basic, token, apikey, secret, password, credential,
 *   or auth keywords, which may contain bank credentials or provider secrets.
 */
fun sanitizeForLog(input: String): String {
    val withoutQuery = input.replace(Regex("\\?[^\\s#]*"), "?[REDACTED]")
    return withoutQuery.replace(
        Regex("(?i)(bearer|basic|token|apikey|api[_-]key|secret|password|credential|auth)(\\s*[:=]\\s*|\\s+)\\S+"),
        "$1=[REDACTED]",
    )
}
