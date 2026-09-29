import { describe, expect, it } from 'vitest';
import {
  backoffMillis,
  isUuidV4,
  newPaymentIdempotencyKey,
  orchestratePayment,
} from './paymentOrchestrator';

class GatewayError extends Error {
  constructor(
    message: string,
    public status: number,
  ) {
    super(message);
  }
}

describe('payment orchestrator', () => {
  it('generates UUID v4 keys', () => {
    const keys = new Set(Array.from({ length: 20 }, () => newPaymentIdempotencyKey()));
    expect(keys.size).toBe(20);
    for (const key of keys) expect(isUuidV4(key)).toBe(true);
    expect(isUuidV4('not-a-uuid')).toBe(false);
  });

  it('backs off exponentially and caps the delay', () => {
    expect(backoffMillis(0, 0)).toBe(200);
    expect(backoffMillis(1, 0)).toBe(400);
    expect(backoffMillis(2, 0)).toBe(800);
    expect(backoffMillis(4, 0)).toBe(1600);
    expect(backoffMillis(0, 1)).toBe(300);
  });

  it('retries 502 and 504 with the same key, method, and session', async () => {
    const statuses = [502, 504, 200];
    const seen: { idempotencyKey: string; method: string; sessionId: string }[] = [];
    const sleeps: number[] = [];
    const key = newPaymentIdempotencyKey();
    const result = await orchestratePayment({
      idempotencyKey: key,
      method: 'bank',
      sessionId: 'room-keep',
      random: () => 0,
      sleep: async (ms) => {
        sleeps.push(ms);
      },
      post: async (attempt) => {
        seen.push(attempt);
        const status = statuses.shift();
        if (status !== 200) throw new GatewayError('gateway', status ?? 502);
        return { ok: true, amountMinor: 2599 };
      },
    });
    expect(result).toEqual({ ok: true, amountMinor: 2599 });
    expect(seen).toEqual([
      { idempotencyKey: key, method: 'bank', sessionId: 'room-keep' },
      { idempotencyKey: key, method: 'bank', sessionId: 'room-keep' },
      { idempotencyKey: key, method: 'bank', sessionId: 'room-keep' },
    ]);
    expect(sleeps).toEqual([200, 400]);
  });

  it('stops after three gateway timeouts and keeps the caller key', async () => {
    let calls = 0;
    const key = newPaymentIdempotencyKey();
    await expect(
      orchestratePayment({
        idempotencyKey: key,
        method: 'card',
        sessionId: 'room-keep',
        random: () => 0,
        sleep: async () => undefined,
        post: async (attempt) => {
          calls += 1;
          expect(attempt.idempotencyKey).toBe(key);
          expect(attempt.method).toBe('card');
          throw new GatewayError('gateway', calls === 3 ? 504 : 502);
        },
      }),
    ).rejects.toThrow(/same key/);
    expect(calls).toBe(3);
  });

  it('does not retry a business HTTP error or an invalid key', async () => {
    let calls = 0;
    const key = newPaymentIdempotencyKey();
    await expect(
      orchestratePayment({
        idempotencyKey: key,
        method: 'card',
        sessionId: 'room-keep',
        sleep: async () => undefined,
        post: async () => {
          calls += 1;
          throw new GatewayError('Invalid amount', 400);
        },
      }),
    ).rejects.toThrow('Invalid amount');
    expect(calls).toBe(1);

    calls = 0;
    await expect(
      orchestratePayment({
        idempotencyKey: 'payment-1',
        method: 'bank',
        sessionId: 'room-keep',
        post: async () => {
          calls += 1;
          return { ok: true };
        },
      }),
    ).rejects.toThrow(/UUID v4/);
    expect(calls).toBe(0);
  });
});
