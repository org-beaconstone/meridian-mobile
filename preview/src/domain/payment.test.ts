import { describe, expect, it } from 'vitest';
import {
  QUOTE_EXPIRED_MESSAGE,
  INVALID_IBAN_MESSAGE,
  formatEur,
  gatewayBackoffMilliseconds,
  isUuidV4,
  isValidIban,
  lockQuote,
  makeIdempotencyKey,
  nextIdempotencyKey,
  parseFxQuote,
  quoteExpired,
  remainingSeconds,
  submissionBlockReason,
  submitPaymentWithRetry,
} from './payment';

describe('payment orchestrator', () => {
  it('checks IBAN with MOD-97', () => {
    expect(isValidIban('GB82WEST12345698765432')).toBe(true);
    expect(isValidIban('GB82 WEST 1234 5698 7654 32')).toBe(true);
    expect(isValidIban('de89 3704 0044 0532 0130 00')).toBe(true);
    expect(isValidIban('FR1420041010050500013M02606')).toBe(true);
    expect(isValidIban('GB82WEST12345698765433')).toBe(false);
    expect(isValidIban('DE89370400440532013001')).toBe(false);
    expect(isValidIban('')).toBe(false);
    expect(isValidIban('GB82')).toBe(false);
  });

  it('generates a UUID v4 idempotency key and can retain it', () => {
    const key = makeIdempotencyKey();
    expect(isUuidV4(key)).toBe(true);
    expect(isUuidV4('aaaaaaaa-bbbb-1ccc-8ddd-eeeeeeeeeeee')).toBe(false);
    expect(nextIdempotencyKey(key, true)).toBe(key);
    expect(nextIdempotencyKey(key, false)).not.toBe(key);
  });

  it('locks a quote for 60 seconds and honours an earlier server expiry', () => {
    const lockedAt = 1_700_000_000_000;
    const quote = parseFxQuote({
      quoteId: 'q-1',
      amountMinor: 1000,
      targetAmountMinor: 1170,
      rate: '1.1700',
      expiresInSeconds: 60,
    });
    const lock = lockQuote(quote, lockedAt);
    expect(remainingSeconds(lock, lockedAt)).toBe(60);
    expect(quoteExpired(lock, lockedAt)).toBe(false);
    expect(remainingSeconds(lock, lockedAt + 60_000)).toBe(0);
    expect(quoteExpired(lock, lockedAt + 60_000)).toBe(true);
    const sooner = lockQuote(
      { ...quote, serverExpiresAtEpochMs: lockedAt + 15_000 },
      lockedAt,
    );
    expect(sooner.expiresAtEpochMs).toBe(lockedAt + 15_000);
    expect(formatEur(1170)).toBe('€11.70');
  });

  it('blocks confirmation when the quote expired or the IBAN is invalid', () => {
    const lockedAt = 1_700_000_000_000;
    const lock = lockQuote(
      parseFxQuote({ id: 'q-1', sourceAmountMinor: 1000, targetAmountMinor: 1170, rate: 1.17 }),
      lockedAt,
    );
    expect(
      submissionBlockReason({
        currency: 'EUR',
        method: 'bank',
        iban: 'GB82WEST12345698765432',
        quote: lock,
        amountMinor: 1000,
        nowEpochMs: lockedAt,
      }),
    ).toBeNull();
    expect(
      submissionBlockReason({
        currency: 'EUR',
        method: 'bank',
        iban: 'GB82WEST12345698765432',
        quote: lock,
        amountMinor: 1000,
        nowEpochMs: lockedAt + 60_000,
      }),
    ).toBe(QUOTE_EXPIRED_MESSAGE);
    expect(
      submissionBlockReason({
        currency: 'GBP',
        method: 'bank',
        iban: 'GB00',
        quote: null,
        amountMinor: 1000,
        nowEpochMs: lockedAt,
      }),
    ).toBe(INVALID_IBAN_MESSAGE);
    expect(
      submissionBlockReason({
        currency: 'GBP',
        method: 'card',
        iban: '',
        quote: null,
        amountMinor: 1000,
        nowEpochMs: lockedAt,
      }),
    ).toBeNull();
  });

  it('retries HTTP 502 and 504 with the same key and method', async () => {
    const key = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
    const seen: { key: string; method: string }[] = [];
    const delays: number[] = [];
    let calls = 0;
    const result = await submitPaymentWithRetry({
      idempotencyKey: key,
      method: 'bank',
      sleep: async (milliseconds) => {
        delays.push(milliseconds);
      },
      isGatewayTimeout: (error) =>
        typeof error === 'object' &&
        error !== null &&
        'status' in error &&
        ((error as { status: number }).status === 502 || (error as { status: number }).status === 504),
      send: async (attemptKey, method) => {
        calls += 1;
        seen.push({ key: attemptKey, method });
        if (calls < 3) {
          const status = calls === 1 ? 502 : 504;
          throw { status };
        }
        return { ok: true };
      },
    });
    expect(result).toEqual({ ok: true });
    expect(seen).toEqual([
      { key, method: 'bank' },
      { key, method: 'bank' },
      { key, method: 'bank' },
    ]);
    expect(delays).toEqual([200, 400]);
    expect(gatewayBackoffMilliseconds(3)).toBe(800);
  });

  it('does not retry client errors or provider unavailable', async () => {
    for (const status of [400, 409, 422, 503]) {
      let calls = 0;
      await expect(
        submitPaymentWithRetry({
          idempotencyKey: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
          method: 'card',
          sleep: async () => {
            throw new Error('should not sleep');
          },
          isGatewayTimeout: (error) =>
            typeof error === 'object' &&
            error !== null &&
            'status' in error &&
            ((error as { status: number }).status === 502 || (error as { status: number }).status === 504),
          send: async () => {
            calls += 1;
            throw { status };
          },
        }),
      ).rejects.toEqual({ status });
      expect(calls).toBe(1);
    }
  });
});
