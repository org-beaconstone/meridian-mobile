// MARK: - Trace Context (W3C Trace Context §3.2)

/** Generates a 128-bit trace ID as 32 lowercase hex characters. */
export function generateTraceId(): string {
  return crypto.randomUUID().replace(/-/g, '').toLowerCase();
}

/** Generates a 64-bit span ID as 16 lowercase hex characters. */
export function generateSpanId(): string {
  return crypto.randomUUID().replace(/-/g, '').toLowerCase().slice(0, 16);
}

/**
 * Builds a W3C `traceparent` header value.
 * Format: `00-{traceId}-{spanId}-01`
 */
export function traceparent(traceId: string, spanId: string): string {
  return `00-${traceId}-${spanId}-01`;
}

// MARK: - Payment Outcome

export type PaymentOutcome = 'success' | 'declined' | 'pending' | 'error';

// MARK: - Payment Journey Event

/** Telemetry emitted at the conclusion of a payment journey. */
export type PaymentJourneyEvent = {
  /** Session trace identifier propagated through the request chain. */
  traceId: string;
  /** Age of the last fetched catalog in seconds; null if catalog was never fetched. */
  catalogAgeSeconds: number | null;
  /** Total number of payment methods advertised by the catalog. */
  methodCount: number | null;
  /** Whether Strong Customer Authentication applies (true for card payments via Adyen). */
  scaInvoked: boolean;
  /** Round-trip latency of the payment network request in milliseconds. */
  latencyMs: number;
  /** Terminal outcome of the payment journey. */
  outcome: PaymentOutcome;
  /** ISO 8601 UTC timestamp of the event. */
  timestamp: string;
};

// MARK: - Audit Log Entry

/**
 * A sanitised audit record for a single payment attempt.
 * No raw credentials, tokens, or URLs are stored.
 */
export type AuditLogEntry = {
  /** Session trace identifier. */
  traceId: string;
  /** ISO 8601 UTC timestamp. */
  timestamp: string;
  /** Action label, e.g. "PAYMENT_SUBMITTED" or "PAYMENT_ERROR". */
  action: string;
  /** SHA-256 hex digest of the raw idempotency key. */
  hashedIdempotencyKey: string;
  /** demoDate from the catalog response, used for catalog-version correlation. */
  catalogVersion: string | null;
  /** Payment method name ("card" or "bank"); no provider credentials included. */
  paymentMethod: string;
  /** Terminal outcome string. */
  outcome: string;
};

// MARK: - Telemetry Configuration

/** Configuration for payment telemetry and audit logging. */
export type TelemetryConfig = {
  /**
   * Fraction of failed journeys to emit as audit entries: 0.0 = none, 1.0 = all.
   * Successful journeys are always audited regardless of this rate.
   * Must be in [0.0, 1.0].
   */
  failedJourneySamplingRate: number;
  /** Called with a telemetry event at the conclusion of every payment attempt. */
  onEvent?: (event: PaymentJourneyEvent) => void;
  /** Called with an audit log entry for every sampled payment attempt. */
  onAudit?: (entry: AuditLogEntry) => void;
};

/** Validates that a sampling rate is in [0.0, 1.0]. */
export function assertValidSamplingRate(rate: number): void {
  if (rate < 0 || rate > 1) {
    throw new RangeError(`failedJourneySamplingRate must be in [0.0, 1.0], got ${rate}`);
  }
}

// MARK: - SHA-256

/** Returns the SHA-256 hex digest of a UTF-8 string. */
export async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

// MARK: - Sanitization

/**
 * Redacts URLs, bearer tokens, UK sort codes, and 8-digit account numbers from a string.
 * Apply to any free-form text before including it in an audit entry.
 */
export function sanitizeForAudit(input: string): string {
  return input
    .replace(/https?:\/\/\S+/g, '[URL]')
    .replace(/Bearer\s+[A-Za-z0-9\-._~+/]+=*/gi, 'Bearer [REDACTED]')
    .replace(/\b\d{2}-\d{2}-\d{2}\b/g, '[SORT-CODE]')
    .replace(/\b\d{8}\b/g, '[ACCOUNT]');
}
