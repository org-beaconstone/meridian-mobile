/** Browser companion copy of the native payment orchestrator. Swift and Kotlin own the device clients. */

export const QUOTE_LOCK_MS = 60_000;
export const MAX_PAYMENT_ATTEMPTS = 3;
export const QUOTE_EXPIRED_MESSAGE =
  'This conversion rate has expired. Refresh the conversion rate before confirming.';
export const INVALID_IBAN_MESSAGE = 'Enter a valid recipient IBAN before submitting.';

const UUID_V4 =
  /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/;

export type PayCurrency = 'GBP' | 'EUR';
export type PayMethod = 'card' | 'bank';

export type FxQuote = {
  quoteId: string;
  sourceCurrency: string;
  targetCurrency: string;
  sourceAmountMinor: number;
  targetAmountMinor: number;
  rate: string;
  expiresInSeconds: number;
  serverExpiresAtEpochMs: number | null;
};

export type FxQuoteLock = FxQuote & {
  lockedAtEpochMs: number;
  expiresAtEpochMs: number;
};

export function normalizeIban(raw: string): string {
  return raw.toUpperCase().replace(/\s+/g, '');
}

/** ISO 13616 MOD-97. Letters expand to A=10 … Z=35. A valid IBAN has remainder 1. */
export function isValidIban(raw: string): boolean {
  const iban = normalizeIban(raw);
  if (!/^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$/.test(iban)) return false;
  const rearranged = iban.slice(4) + iban.slice(0, 4);
  let remainder = 0;
  for (const character of rearranged) {
    const digits =
      character >= '0' && character <= '9'
        ? character
        : String(character.charCodeAt(0) - 55);
    for (const digit of digits) {
      remainder = (remainder * 10 + Number(digit)) % 97;
    }
  }
  return remainder === 1;
}

export function isUuidV4(value: string): boolean {
  return UUID_V4.test(value);
}

export function makeIdempotencyKey(): string {
  const key = crypto.randomUUID();
  if (!isUuidV4(key)) throw new Error('Platform UUID must be version 4');
  return key;
}

export function nextIdempotencyKey(current: string, retain: boolean): string {
  return retain ? current : makeIdempotencyKey();
}

export function formatEur(cents: number): string {
  const negative = cents < 0;
  const absolute = Math.abs(cents);
  return `${negative ? '-' : ''}€${Math.trunc(absolute / 100)}.${String(absolute % 100).padStart(2, '0')}`;
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
  const sourceAmountMinor = integerField(record.sourceAmountMinor ?? record.amountMinor);
  const targetAmountMinor = integerField(record.targetAmountMinor);
  if (!quoteId || sourceAmountMinor === null || targetAmountMinor === null) {
    throw new Error('Invalid FX quote');
  }
  const rate =
    typeof record.rate === 'string'
      ? record.rate
      : typeof record.rate === 'number' && Number.isFinite(record.rate)
        ? String(record.rate)
        : '';
  const expiresInSeconds = integerField(record.expiresInSeconds) ?? 60;
  let serverExpiresAtEpochMs: number | null = null;
  if (typeof record.expiresAt === 'string') {
    const parsed = Date.parse(record.expiresAt);
    serverExpiresAtEpochMs = Number.isNaN(parsed) ? null : parsed;
  }
  return {
    quoteId,
    sourceCurrency: typeof record.sourceCurrency === 'string' ? record.sourceCurrency : 'GBP',
    targetCurrency: typeof record.targetCurrency === 'string' ? record.targetCurrency : 'EUR',
    sourceAmountMinor,
    targetAmountMinor,
    rate,
    expiresInSeconds,
    serverExpiresAtEpochMs,
  };
}

function integerField(value: unknown): number | null {
  if (typeof value !== 'number' || !Number.isInteger(value)) return null;
  return value;
}

export function lockQuote(quote: FxQuote, lockedAtEpochMs: number): FxQuoteLock {
  const localExpiry = lockedAtEpochMs + QUOTE_LOCK_MS;
  const server = quote.serverExpiresAtEpochMs;
  const expiresAtEpochMs = server !== null && server < localExpiry ? server : localExpiry;
  return { ...quote, lockedAtEpochMs, expiresAtEpochMs };
}

export function remainingSeconds(lock: FxQuoteLock, nowEpochMs: number): number {
  const leftMs = lock.expiresAtEpochMs - nowEpochMs;
  if (leftMs <= 0) return 0;
  return Math.min(60, Math.ceil(leftMs / 1000));
}

export function quoteExpired(lock: FxQuoteLock, nowEpochMs: number): boolean {
  return nowEpochMs >= lock.expiresAtEpochMs;
}

export function ibanRequired(currency: PayCurrency, method: PayMethod): boolean {
  return currency === 'EUR' || method === 'bank';
}

export function ibanBlockReason(currency: PayCurrency, method: PayMethod, iban: string): string | null {
  if (ibanRequired(currency, method) || normalizeIban(iban).length > 0) {
    if (!isValidIban(iban)) return INVALID_IBAN_MESSAGE;
  }
  return null;
}

export function submissionBlockReason(input: {
  currency: PayCurrency;
  method: PayMethod;
  iban: string;
  quote: FxQuoteLock | null;
  amountMinor: number;
  nowEpochMs: number;
}): string | null {
  const ibanError = ibanBlockReason(input.currency, input.method, input.iban);
  if (ibanError) return ibanError;
  if (input.currency === 'EUR') {
    if (
      !input.quote ||
      input.quote.sourceAmountMinor !== input.amountMinor ||
      quoteExpired(input.quote, input.nowEpochMs)
    ) {
      return QUOTE_EXPIRED_MESSAGE;
    }
  }
  return null;
}

export function isGatewayTimeoutStatus(status: number | undefined): boolean {
  return status === 502 || status === 504;
}

/** Delay before the next attempt. `failedAttempt` is the 1-based count of gateway failures so far. */
export function gatewayBackoffMilliseconds(failedAttempt: number): number {
  if (failedAttempt < 1) throw new Error('failedAttempt');
  const shift = Math.min(failedAttempt - 1, 8);
  return 200 * 2 ** shift;
}

export async function submitPaymentWithRetry<T>(options: {
  idempotencyKey: string;
  method: PayMethod;
  maxAttempts?: number;
  delayMilliseconds?: (failedAttempt: number) => number;
  sleep?: (milliseconds: number) => Promise<void>;
  isGatewayTimeout: (error: unknown) => boolean;
  send: (idempotencyKey: string, method: PayMethod) => Promise<T>;
}): Promise<T> {
  const maxAttempts = options.maxAttempts ?? MAX_PAYMENT_ATTEMPTS;
  const delayMilliseconds = options.delayMilliseconds ?? gatewayBackoffMilliseconds;
  const sleep =
    options.sleep ?? ((milliseconds: number) => new Promise((resolve) => setTimeout(resolve, milliseconds)));
  let attempt = 1;
  for (;;) {
    try {
      return await options.send(options.idempotencyKey, options.method);
    } catch (error) {
      if (!options.isGatewayTimeout(error) || attempt >= maxAttempts) throw error;
      const wait = delayMilliseconds(attempt);
      attempt += 1;
      await sleep(wait);
    }
  }
}
