import { describe, it, expect } from 'vitest';
import {
  generateTraceId,
  generateSpanId,
  traceparent,
  sanitizeForAudit,
  sha256Hex,
  assertValidSamplingRate,
} from './telemetry';

describe('telemetry – trace context', () => {
  it('generateTraceId produces 32 lowercase hex characters', () => {
    const id = generateTraceId();
    expect(id).toMatch(/^[0-9a-f]{32}$/);
  });

  it('generateTraceId produces unique values', () => {
    expect(generateTraceId()).not.toBe(generateTraceId());
  });

  it('generateSpanId produces 16 lowercase hex characters', () => {
    const id = generateSpanId();
    expect(id).toMatch(/^[0-9a-f]{16}$/);
  });

  it('traceparent assembles a valid W3C header', () => {
    const traceId = 'a'.repeat(32);
    const spanId = 'b'.repeat(16);
    expect(traceparent(traceId, spanId)).toBe(`00-${'a'.repeat(32)}-${'b'.repeat(16)}-01`);
  });
});

describe('telemetry – sanitizeForAudit', () => {
  it('redacts HTTP URLs', () => {
    expect(sanitizeForAudit('redirect to http://example.com/token')).toBe(
      'redirect to [URL]',
    );
  });

  it('redacts HTTPS URLs', () => {
    expect(sanitizeForAudit('handoff: https://pay.provider.com/auth?token=abc')).toBe(
      'handoff: [URL]',
    );
  });

  it('redacts Bearer tokens', () => {
    expect(sanitizeForAudit('Authorization: Bearer eyJhbGciOiJSUzI1NiJ9.payload.sig')).toBe(
      'Authorization: Bearer [REDACTED]',
    );
  });

  it('redacts Bearer tokens case-insensitively', () => {
    expect(sanitizeForAudit('BEARER abc123')).toBe('Bearer [REDACTED]');
  });

  it('redacts UK sort codes (NN-NN-NN)', () => {
    expect(sanitizeForAudit('sort code 20-00-01')).toBe('sort code [SORT-CODE]');
  });

  it('redacts 8-digit account numbers', () => {
    expect(sanitizeForAudit('account 12345678')).toBe('account [ACCOUNT]');
  });

  it('leaves clean text unchanged', () => {
    expect(sanitizeForAudit('PAYMENT_SUBMITTED')).toBe('PAYMENT_SUBMITTED');
  });

  it('redacts multiple sensitive values in one string', () => {
    const input = 'url https://example.com sort 20-00-01 acc 12345678';
    const result = sanitizeForAudit(input);
    expect(result).not.toContain('https://');
    expect(result).not.toContain('20-00-01');
    expect(result).not.toContain('12345678');
    expect(result).toContain('[URL]');
    expect(result).toContain('[SORT-CODE]');
    expect(result).toContain('[ACCOUNT]');
  });
});

describe('telemetry – sha256Hex', () => {
  it('returns the correct SHA-256 digest for a known input', async () => {
    // SHA-256("test") = 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08
    const hash = await sha256Hex('test');
    expect(hash).toBe('9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08');
  });

  it('returns 64 lowercase hex characters', async () => {
    const hash = await sha256Hex('idempotency-key-12345');
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
  });

  it('produces different digests for different inputs', async () => {
    const h1 = await sha256Hex('key-a');
    const h2 = await sha256Hex('key-b');
    expect(h1).not.toBe(h2);
  });

  it('hashes the empty string correctly', async () => {
    // SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    const hash = await sha256Hex('');
    expect(hash).toBe('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  });
});

describe('telemetry – assertValidSamplingRate', () => {
  it('accepts 0.0', () => {
    expect(() => assertValidSamplingRate(0.0)).not.toThrow();
  });

  it('accepts 1.0', () => {
    expect(() => assertValidSamplingRate(1.0)).not.toThrow();
  });

  it('accepts 0.5', () => {
    expect(() => assertValidSamplingRate(0.5)).not.toThrow();
  });

  it('rejects values above 1.0', () => {
    expect(() => assertValidSamplingRate(1.1)).toThrow(RangeError);
  });

  it('rejects negative values', () => {
    expect(() => assertValidSamplingRate(-0.1)).toThrow(RangeError);
  });
});
