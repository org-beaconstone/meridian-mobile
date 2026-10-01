import { describe, it, expect } from 'vitest';
import {
  generateTraceId,
  generateSpanId,
  buildTraceparent,
  hashIdempotencyKey,
  sanitizeForLog,
  toLogLine,
  type AuditLogEntry,
} from './telemetry';

describe('telemetry: trace ID generation', () => {
  it('generateTraceId produces a 32-char lowercase hex string', () => {
    const id = generateTraceId();
    expect(id).toHaveLength(32);
    expect(id).toMatch(/^[0-9a-f]{32}$/);
  });

  it('generateTraceId produces unique IDs', () => {
    expect(generateTraceId()).not.toBe(generateTraceId());
  });

  it('generateSpanId produces a 16-char lowercase hex string', () => {
    const id = generateSpanId();
    expect(id).toHaveLength(16);
    expect(id).toMatch(/^[0-9a-f]{16}$/);
  });

  it('generateSpanId produces unique IDs', () => {
    expect(generateSpanId()).not.toBe(generateSpanId());
  });

  it('buildTraceparent produces W3C traceparent format', () => {
    const traceId = generateTraceId();
    const spanId = generateSpanId();
    const tp = buildTraceparent(traceId, spanId);
    expect(tp).toBe(`00-${traceId}-${spanId}-01`);
    const parts = tp.split('-');
    expect(parts).toHaveLength(4);
    expect(parts[0]).toBe('00');
    expect(parts[1]).toHaveLength(32);
    expect(parts[2]).toHaveLength(16);
    expect(parts[3]).toBe('01');
  });
});

describe('telemetry: hashIdempotencyKey', () => {
  it('produces a 64-char lowercase hex string', async () => {
    const hash = await hashIdempotencyKey('some-key');
    expect(hash).toHaveLength(64);
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
  });

  it('is deterministic for the same input', async () => {
    const key = 'stable-idempotency-key';
    expect(await hashIdempotencyKey(key)).toBe(await hashIdempotencyKey(key));
  });

  it('produces different hashes for different inputs', async () => {
    const h1 = await hashIdempotencyKey('key-alpha');
    const h2 = await hashIdempotencyKey('key-beta');
    expect(h1).not.toBe(h2);
  });

  it('matches the known SHA-256 digest of "test"', async () => {
    const expected = '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';
    expect(await hashIdempotencyKey('test')).toBe(expected);
  });
});

describe('telemetry: sanitizeForLog', () => {
  it('redacts URL query parameters', () => {
    const result = sanitizeForLog('https://provider.example.com/callback?token=abc123&session=xyz');
    expect(result).toContain('?[REDACTED]');
    expect(result).not.toContain('abc123');
    expect(result).not.toContain('session=xyz');
  });

  it('redacts bearer token values', () => {
    const result = sanitizeForLog('Authorization: bearer eyJhbGciOiJSUzI1NiJ9.payload.sig');
    expect(result).toContain('[REDACTED]');
    expect(result).not.toContain('eyJhbGciOiJSUzI1NiJ9');
    // keyword retained
    expect(result.toLowerCase()).toContain('bearer');
  });

  it('redacts password values', () => {
    const result = sanitizeForLog('password=s3cr3tP@ss!');
    expect(result).toContain('[REDACTED]');
    expect(result).not.toContain('s3cr3tP@ss!');
  });

  it('redacts api_key values', () => {
    const result = sanitizeForLog('api_key=live_12345abcde');
    expect(result).toContain('[REDACTED]');
    expect(result).not.toContain('live_12345abcde');
  });

  it('redacts secret values (case-insensitive)', () => {
    const result = sanitizeForLog('Secret: mysecretvalue');
    expect(result).toContain('[REDACTED]');
    expect(result).not.toContain('mysecretvalue');
  });

  it('leaves plain text unchanged', () => {
    const input = 'payment completed for recipient northline-studio';
    expect(sanitizeForLog(input)).toBe(input);
  });

  it('leaves a URL without query params unchanged', () => {
    const input = 'https://api.example.com/payments';
    expect(sanitizeForLog(input)).toBe(input);
  });
});

describe('telemetry: toLogLine', () => {
  it('includes required fields trace, ts, event', () => {
    const entry: AuditLogEntry = {
      traceId: 'abcdef1234567890abcdef1234567890',
      timestamp: '2026-09-18T12:00:00Z',
      event: 'payment.completed',
    };
    const line = toLogLine(entry);
    expect(line).toContain('trace=abcdef1234567890abcdef1234567890');
    expect(line).toContain('ts=2026-09-18T12:00:00Z');
    expect(line).toContain('event=payment.completed');
  });

  it('includes all optional fields when present', () => {
    const entry: AuditLogEntry = {
      traceId: 'abc',
      timestamp: '2026-09-18T12:00:00Z',
      event: 'payment.completed',
      outcome: 'success',
      hashedIdempotencyKey: 'deadbeef',
      catalogAgeDays: 5,
      methodCount: 2,
      scaInvoked: true,
      latencyMs: 142,
      amountMinor: 1000,
      paymentMethod: 'card',
    };
    const line = toLogLine(entry);
    expect(line).toContain('outcome=success');
    expect(line).toContain('idem_hash=deadbeef');
    expect(line).toContain('catalog_age_days=5');
    expect(line).toContain('method_count=2');
    expect(line).toContain('sca=true');
    expect(line).toContain('latency_ms=142');
    expect(line).toContain('amount_pence=1000');
    expect(line).toContain('method=card');
  });

  it('omits undefined fields', () => {
    const entry: AuditLogEntry = {
      traceId: 'abc',
      timestamp: '2026-09-18T12:00:00Z',
      event: 'payment.completed',
    };
    const line = toLogLine(entry);
    expect(line).not.toContain('outcome=');
    expect(line).not.toContain('idem_hash=');
    expect(line).not.toContain('latency_ms=');
    expect(line).not.toContain('sca=');
  });

  it('does not include the raw idempotency key', async () => {
    const rawKey = 'raw-secret-idempotency-key-9876';
    const entry: AuditLogEntry = {
      traceId: 'abc',
      timestamp: '2026-09-18T12:00:00Z',
      event: 'payment.completed',
      hashedIdempotencyKey: await hashIdempotencyKey(rawKey),
    };
    const line = toLogLine(entry);
    expect(line).not.toContain(rawKey);
    expect(line).toContain('idem_hash=');
  });
});
