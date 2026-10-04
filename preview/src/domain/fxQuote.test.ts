import { describe, expect, it } from 'vitest';
import {
  ACCOUNT_CURRENCY,
  FX_COPY,
  buildPaymentPayload,
  fxQuoteRequestBody,
  lockQuote,
  parseFxQuote,
  preserveDraftOnRateRefresh,
  rateLockBlockReason,
  remainingSeconds,
} from './fxQuote';

const lockedAt = Date.parse('2026-10-04T09:00:00.000Z');

function sampleQuote(overrides: Record<string, unknown> = {}) {
  return parseFxQuote({
    quoteId: 'quote-1',
    sourceCurrency: 'GBP',
    targetCurrency: 'EUR',
    sourceAmountMinor: 1250,
    targetAmountMinor: 1463,
    rate: '1.17',
    expiresInSeconds: 60,
    ...overrides,
  });
}

describe('FX quote lock', () => {
  it('requests source and target currencies with the GBP amount', () => {
    expect(fxQuoteRequestBody('GBP', 'EUR', 1250)).toEqual({
      sourceCurrency: 'GBP',
      targetCurrency: 'EUR',
      amountMinor: 1250,
    });
  });

  it('accepts a numeric rate and an id alias', () => {
    const quote = parseFxQuote({ id: 'q-9', rate: 1.1714, amountMinor: 500, expiresInSeconds: 60 });
    expect(quote.quoteId).toBe('q-9');
    expect(quote.rate).toBe('1.1714');
    expect(quote.sourceAmountMinor).toBe(500);
  });

  it('locks the rate for 60 seconds and lets a sooner server expiry win', () => {
    const full = lockQuote(sampleQuote(), 'GBP', 'EUR', 1250, lockedAt);
    expect(remainingSeconds(full, lockedAt)).toBe(60);
    expect(remainingSeconds(full, lockedAt + 59_100)).toBe(1);
    expect(remainingSeconds(full, lockedAt + 60_000)).toBe(0);

    const sooner = lockQuote(
      sampleQuote({ expiresAt: '2026-10-04T09:00:15.000Z', expiresInSeconds: 60 }),
      'GBP',
      'EUR',
      1250,
      lockedAt,
    );
    expect(sooner.expiresAtEpochMs - lockedAt).toBe(15_000);

    const capped = lockQuote(sampleQuote({ expiresInSeconds: 120 }), 'GBP', 'EUR', 1250, lockedAt);
    expect(capped.expiresAtEpochMs - lockedAt).toBe(60_000);
  });

  it('blocks a stale or missing lock and allows a same-currency payment without a quote', () => {
    const lock = lockQuote(sampleQuote(), 'GBP', 'EUR', 1250, lockedAt);
    expect(
      rateLockBlockReason({
        sourceCurrency: 'GBP',
        targetCurrency: 'EUR',
        amountMinor: 1250,
        quote: null,
        nowEpochMs: lockedAt,
      }),
    ).toBe(FX_COPY.unavailable);
    expect(
      rateLockBlockReason({
        sourceCurrency: 'GBP',
        targetCurrency: 'EUR',
        amountMinor: 1250,
        quote: lock,
        nowEpochMs: lockedAt + 60_000,
      }),
    ).toBe(FX_COPY.expired);
    expect(
      rateLockBlockReason({
        sourceCurrency: ACCOUNT_CURRENCY,
        targetCurrency: 'GBP',
        amountMinor: 1250,
        quote: null,
        nowEpochMs: lockedAt,
      }),
    ).toBeNull();
  });

  it('attaches quoteId only while the cross-currency lock is valid', () => {
    const lock = lockQuote(sampleQuote(), 'GBP', 'EUR', 1250, lockedAt);
    const ready = buildPaymentPayload({
      recipientId: 'northline-studio',
      amountMinor: 1250,
      method: 'card',
      note: 'Invoice',
      scenario: 'success',
      sourceCurrency: 'GBP',
      targetCurrency: 'EUR',
      quote: lock,
      nowEpochMs: lockedAt + 1000,
    });
    expect(ready.ok).toBe(true);
    if (ready.ok) expect(ready.body.quoteId).toBe('quote-1');

    const stale = buildPaymentPayload({
      recipientId: 'northline-studio',
      amountMinor: 1250,
      method: 'card',
      note: 'Invoice',
      scenario: 'success',
      sourceCurrency: 'GBP',
      targetCurrency: 'EUR',
      quote: lock,
      nowEpochMs: lockedAt + 60_000,
    });
    expect(stale).toEqual({ ok: false, error: FX_COPY.expired });

    const gbp = buildPaymentPayload({
      recipientId: 'northline-studio',
      amountMinor: 1250,
      method: 'bank',
      note: 'Invoice',
      scenario: 'success',
      sourceCurrency: 'GBP',
      targetCurrency: 'GBP',
      quote: lock,
      nowEpochMs: lockedAt,
    });
    expect(gbp.ok).toBe(true);
    if (gbp.ok) expect(gbp.body.quoteId).toBeUndefined();
  });

  it('keeps the entered draft when the rate is refreshed', () => {
    const draft = {
      recipientId: 'northline-studio',
      amount: '12.50',
      note: 'Studio invoice',
      method: 'card' as const,
      targetCurrency: 'EUR',
      idempotencyKey: 'key-kept',
    };
    expect(preserveDraftOnRateRefresh(draft)).toEqual(draft);
  });
});
