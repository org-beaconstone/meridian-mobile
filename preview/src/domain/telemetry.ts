/**
 * Payment audit logging and distributed tracing utilities for the Meridian preview.
 *
 * These helpers produce W3C-traceparent trace IDs, hash idempotency keys via SHA-256,
 * sanitize strings before audit logging, and format structured log entries.
 * No raw credentials, bearer tokens, handoff URLs, or unhashed idempotency keys
 * appear in any output produced by this module.
 */

// MARK: - Types

/** Configuration for payment audit logging and distributed tracing. */
export interface TelemetryConfig {
  /**
   * Fraction of failed payment journeys to emit as audit log entries.
   * Range [0, 1]. 1.0 logs every failure; 0.0 suppresses all failure logs.
   * Successful journeys are always emitted.
   */
  failedJourneySampleRate: number;
  /** Receives each emitted AuditLogEntry. Defaults to console.error. */
  onEntry?: (entry: AuditLogEntry) => void;
}

/** A single structured audit log entry for one payment journey event. */
export interface AuditLogEntry {
  /** Trace ID linking this entry to a distributed trace (32 hex chars). */
  traceId: string;
  /** ISO-8601 UTC timestamp when this entry was produced. */
  timestamp: string;
  /** Event name: "payment.submitted" or "payment.completed". */
  event: string;
  /** Terminal outcome: "success" | "declined" | "pending" | "error". */
  outcome?: string;
  /** SHA-256 hex digest of the raw idempotency key. The raw key is never stored. */
  hashedIdempotencyKey?: string;
  /** Days elapsed since the catalog's demoDate. */
  catalogAgeDays?: number;
  /** Total payment method slots across all catalog providers. */
  methodCount?: number;
  /** True when Strong Customer Authentication (SCA/PSD2) was invoked. */
  scaInvoked?: boolean;
  /** End-to-end API request latency in milliseconds. */
  latencyMs?: number;
  /** Payment amount in GBP pence (integer). */
  amountMinor?: number;
  /** Payment method: "card" or "bank". */
  paymentMethod?: string;
}

// MARK: - Trace ID generation

/** Generate a 32-character lowercase hex trace ID (W3C trace-id format). */
export function generateTraceId(): string {
  return crypto.randomUUID().replace(/-/g, '');
}

/** Generate a 16-character lowercase hex span ID (W3C parent-id format). */
export function generateSpanId(): string {
  return crypto.randomUUID().replace(/-/g, '').slice(0, 16);
}

/**
 * Build a W3C traceparent header value.
 * Format: "00-{32-hex traceId}-{16-hex spanId}-01"
 */
export function buildTraceparent(traceId: string, spanId: string): string {
  return `00-${traceId}-${spanId}-01`;
}

// MARK: - Hash

/**
 * Compute the SHA-256 hex digest of a raw idempotency key.
 * Use the returned hash for audit logging; never log the original key.
 */
export async function hashIdempotencyKey(rawKey: string): Promise<string> {
  const data = new TextEncoder().encode(rawKey);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, '0')).join('');
}

// MARK: - Sanitize

/**
 * Sanitize a string before writing it to an audit log.
 *
 * - Removes URL query parameters, which can carry OAuth tokens, session codes, or API keys.
 * - Redacts values following bearer, basic, token, apikey, secret, password, credential,
 *   or auth keywords, which may contain bank credentials or provider secrets.
 */
export function sanitizeForLog(input: string): string {
  // Strip URL query parameters
  let result = input.replace(/\?[^\s#]*/g, '?[REDACTED]');
  // Redact auth credential patterns (keyword=value, keyword: value, or keyword value)
  result = result.replace(
    /(bearer|basic|token|apikey|api[_-]key|secret|password|credential|auth)(\s*[:=]\s*|\s+)\S+/gi,
    (_, keyword: string) => `${keyword}=[REDACTED]`,
  );
  return result;
}

// MARK: - Log line formatting

/**
 * Format an AuditLogEntry as a single structured log line.
 * Only non-undefined fields are included. Safe to write to any log sink.
 */
export function toLogLine(entry: AuditLogEntry): string {
  const parts = [
    `trace=${entry.traceId}`,
    `ts=${entry.timestamp}`,
    `event=${entry.event}`,
  ];
  if (entry.outcome !== undefined) parts.push(`outcome=${entry.outcome}`);
  if (entry.hashedIdempotencyKey !== undefined)
    parts.push(`idem_hash=${entry.hashedIdempotencyKey}`);
  if (entry.catalogAgeDays !== undefined)
    parts.push(`catalog_age_days=${entry.catalogAgeDays}`);
  if (entry.methodCount !== undefined) parts.push(`method_count=${entry.methodCount}`);
  if (entry.scaInvoked !== undefined) parts.push(`sca=${entry.scaInvoked}`);
  if (entry.latencyMs !== undefined) parts.push(`latency_ms=${entry.latencyMs}`);
  if (entry.amountMinor !== undefined) parts.push(`amount_pence=${entry.amountMinor}`);
  if (entry.paymentMethod !== undefined) parts.push(`method=${entry.paymentMethod}`);
  return parts.join(' ');
}
