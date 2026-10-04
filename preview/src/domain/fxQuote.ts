/** Browser companion copy of the native FX rate lock. Swift and Kotlin own the device clients. */

export const ACCOUNT_CURRENCY = 'GBP';
export const QUOTE_LOCK_SECONDS = 60;
export const QUOTE_LOCK_MS = QUOTE_LOCK_SECONDS * 1000;

export const FX_COPY = {
  unavailable: "We couldn't lock an exchange rate. Try again.",
  expired:
    'This rate lock has expired. Refresh the rate to continue. Your payment details are unchanged.',
  retry: 'Try again',
  refresh: 'Refresh rate',
  locked: 'Rate locked',
} as const;

export type PayMethod = 'card' | 'bank';

export type FxQuote = {
  quoteId: string;
  sourceCurrency: string;
  targetCurrency: string;
  sourceAmountMinor: number | null;
  targetAmountMinor: number | null;
  rate: string;
  expiresInSeconds: number;
  serverExpiresAtEpochMs: number | null;
};

export type FxQuoteLock = {
  quoteId: string;
  sourceCurrency: string;
  targetCurrency: string;
  sourceAmountMinor: number;
  targetAmountMinor: number | null;
  rate: string;
  expiresAtEpochMs: number;
};

export type PaymentDraft = {
  recipientId: string;
  amount: string;
  note: string;
  method: PayMethod;
  targetCurrency: string;
  idempotencyKey: string;
};

export function isCrossCurrency(source: string, target: string): boolean {
  return source.toUpperCase() !== target.toUpperCase();
}

export function fxQuoteRequestBody(sourceCurrency: string, targetCurrency: string, amountMinor: number) {
  return { sourceCurrency, targetCurrency, amountMinor };
}

/** In-place refresh keeps the draft the customer already entered, including the payment key. */
export function preserveDraftOnRateRefresh(draft: PaymentDraft): PaymentDraft {
  return {
    recipientId: draft.recipientId,
    amount: draft.amount,
    note: draft.note,
    method: draft.method,
    targetCurrency: draft.targetCurrency,
    idempotencyKey: draft.idempotencyKey,
  };
}

export function formatMinor(amountMinor: number, currency: string): string {
  const negative = amountMinor < 0;
  const absolute = Math.abs(amountMinor);
  const text = `${Math.trunc(absolute / 100)}.${String(absolute % 100).padStart(2, '0')}`;
  if (currency.toUpperCase() === 'EUR') return `${negative ? '-' : ''}€${text}`;
  return `${negative ? '-' : ''}£${text}`;
}

function trimRate(number: number): string {
  let text = number.toFixed(6);
  while (text.includes('.') && (text.endsWith('0') || text.endsWith('.'))) {
    text = text.slice(0, -1);
  }
  return text;
}

function integerField(value: unknown): number | null {
  return typeof value === 'number' && Number.isInteger(value) ? value : null;
}

export function parseFxQuote(value: unknown): FxQuote {
  if (!value || typeof value !== 'object') throw new Error('Invalid FX quote');
  const record = value as Record<string, unknown>;
  const quoteId =
    typeof record.quoteId === 'string' && record.quoteId
      ? record.quoteId
      : typeof record.id === 'string'
        ? record.id
        : '';
  if (!quoteId) throw new Error('Invalid FX quote');
  let rate = '';
  if (typeof record.rate === 'string' && record.rate) rate = record.rate;
  else if (typeof record.rate === 'number' && Number.isFinite(record.rate)) rate = trimRate(record.rate);
  if (!rate) throw new Error('Invalid FX quote');
  let serverExpiresAtEpochMs: number | null = null;
  if (typeof record.expiresAt === 'string') {
    const parsed = Date.parse(record.expiresAt);
    serverExpiresAtEpochMs = Number.isNaN(parsed) ? null : parsed;
  } else if (typeof record.expiresAt === 'number' && Number.isFinite(record.expiresAt)) {
    serverExpiresAtEpochMs = record.expiresAt < 10_000_000_000 ? record.expiresAt * 1000 : record.expiresAt;
  }
  return {
    quoteId,
    sourceCurrency: typeof record.sourceCurrency === 'string' ? record.sourceCurrency : '',
    targetCurrency: typeof record.targetCurrency === 'string' ? record.targetCurrency : '',
    sourceAmountMinor: integerField(record.sourceAmountMinor ?? record.amountMinor),
    targetAmountMinor: integerField(record.targetAmountMinor),
    rate,
    expiresInSeconds: integerField(record.expiresInSeconds) ?? QUOTE_LOCK_SECONDS,
    serverExpiresAtEpochMs,
  };
}

export function lockQuote(
  quote: FxQuote,
  sourceCurrency: string,
  targetCurrency: string,
  amountMinor: number,
  lockedAtEpochMs: number,
): FxQuoteLock {
  const windowSeconds = Math.min(QUOTE_LOCK_SECONDS, Math.max(0, quote.expiresInSeconds));
  let expiry = lockedAtEpochMs + windowSeconds * 1000;
  if (quote.serverExpiresAtEpochMs !== null && quote.serverExpiresAtEpochMs < expiry) {
    expiry = quote.serverExpiresAtEpochMs;
  }
  const cap = lockedAtEpochMs + QUOTE_LOCK_MS;
  if (expiry > cap) expiry = cap;
  return {
    quoteId: quote.quoteId,
    sourceCurrency: quote.sourceCurrency || sourceCurrency,
    targetCurrency: quote.targetCurrency || targetCurrency,
    sourceAmountMinor: quote.sourceAmountMinor ?? amountMinor,
    targetAmountMinor: quote.targetAmountMinor,
    rate: quote.rate,
    expiresAtEpochMs: expiry,
  };
}

export function remainingSeconds(lock: FxQuoteLock, nowEpochMs: number): number {
  const left = lock.expiresAtEpochMs - nowEpochMs;
  if (left <= 0) return 0;
  return Math.min(QUOTE_LOCK_SECONDS, Math.ceil(left / 1000));
}

export function quoteExpired(lock: FxQuoteLock, nowEpochMs: number): boolean {
  return nowEpochMs >= lock.expiresAtEpochMs;
}

export function rateLockBlockReason(input: {
  sourceCurrency: string;
  targetCurrency: string;
  amountMinor: number;
  quote: FxQuoteLock | null;
  nowEpochMs: number;
}): string | null {
  if (!isCrossCurrency(input.sourceCurrency, input.targetCurrency)) return null;
  const quote = input.quote;
  if (!quote) return FX_COPY.unavailable;
  const samePair =
    quote.sourceCurrency.toUpperCase() === input.sourceCurrency.toUpperCase() &&
    quote.targetCurrency.toUpperCase() === input.targetCurrency.toUpperCase() &&
    quote.sourceAmountMinor === input.amountMinor &&
    quote.quoteId.length > 0 &&
    !quoteExpired(quote, input.nowEpochMs);
  return samePair ? null : FX_COPY.expired;
}

export function buildPaymentPayload(input: {
  recipientId: string;
  amountMinor: number;
  method: PayMethod;
  note: string;
  scenario: string;
  sourceCurrency: string;
  targetCurrency: string;
  quote: FxQuoteLock | null;
  nowEpochMs: number;
}): { ok: true; body: Record<string, unknown> } | { ok: false; error: string } {
  const block = rateLockBlockReason(input);
  if (block) return { ok: false, error: block };
  const body: Record<string, unknown> = {
    recipientId: input.recipientId,
    amountMinor: input.amountMinor,
    method: input.method,
    note: input.note,
    scenario: input.scenario,
  };
  if (isCrossCurrency(input.sourceCurrency, input.targetCurrency) && input.quote) {
    body.quoteId = input.quote.quoteId;
  }
  return { ok: true, body };
}
