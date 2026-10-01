import { money, parsePence } from './currency';

export const paymentConsentSummary =
  'I authorise Meridian to submit this GBP payment to the named recipient. This rehearsal does not move real money or contact Adyen or Worldpay.';

export const paymentQuoteTTLSeconds = 60;

export type IntentMethod = 'card' | 'bank';
export type IntentDisposition = 'succeeded' | 'declined' | 'actionRequired' | 'retrySameIntent';

export type PaymentReview = {
  recipientName: string;
  recipientDetail: string;
  amountMinor: number;
  feeMinor: number;
  amountLabel: string;
  feeLabel: string;
  methodLabel: string;
  bank: string;
  quoteExpiresAt: string;
  expiryLabel: string;
  consentSummary: string;
  localReference: string;
  currency: 'GBP';
};

export type PaymentIntentResponseBody = {
  ok?: boolean;
  status?: string;
  intentId?: string;
  intent_id?: string;
  state?: unknown;
  error?: string;
  code?: string;
};

export type PaymentIntentHttpResult = {
  statusCode: number;
  body: PaymentIntentResponseBody;
};

export type PaymentIntentSubmission = {
  disposition: IntentDisposition;
  statusCode: number;
  intentId?: string;
  ok: boolean;
  code?: string;
  error?: string;
  message: string;
  idempotencyKey: string;
  payloadHash: string;
  body: PaymentIntentResponseBody;
  terminal: boolean;
};

export class PaymentIntentError extends Error {
  constructor(
    message: string,
    public code: 'validation' | 'duplicate' | 'quote_expired',
  ) {
    super(message);
  }
}

const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const safeToken = /^[A-Za-z0-9_-]{1,100}$/;

export function resolvePaymentIntentsURL(baseURL: string): string {
  const trimmed = baseURL.replace(/\/+$/, '');
  const root = trimmed.endsWith('/api/v1') ? trimmed.slice(0, -'/api/v1'.length) : trimmed;
  return `${root}/api/v2/payment-intents`;
}

export function rehearsalFeeMinor(method: IntentMethod, amountMinor: number): number {
  if (method === 'bank') return 0;
  return Math.max(1, Math.floor((amountMinor * 15 + 500) / 1000));
}

export function baselineBank(method: IntentMethod): string {
  return method === 'card' ? 'Adyen' : 'Worldpay';
}

export function baselineProviderId(method: IntentMethod): string {
  return method === 'card' ? 'adyen' : 'worldpay';
}

export function baselineMethodLabel(method: IntentMethod): string {
  return method === 'card' ? 'Debit card' : 'Bank payment';
}

export function localizedRecipientName(name: string): string {
  return name.trim().normalize('NFC');
}

export function formatUTC(date: Date): string {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

export function localizedQuoteExpiry(iso: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/.exec(iso);
  if (!match) return iso;
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (month < 1 || month > 12) return iso;
  return `${day} ${months[month - 1]} ${match[1]}, ${match[4]}:${match[5]} UTC`;
}

export function isQuoteExpired(quoteExpiresAt: string, now: Date): boolean {
  return formatUTC(now) >= quoteExpiresAt;
}

export function normalizedLocalReference(input: string): { value: string | null; error: string | null } {
  const trimmed = input.trim();
  if (!trimmed) return { value: null, error: 'Local reference is required' };
  if ([...trimmed].length > 200) return { value: null, error: 'Local reference is too long' };
  if ([...trimmed].some((char) => char.charCodeAt(0) < 32 || char.charCodeAt(0) === 127)) {
    return { value: null, error: 'Local reference contains invalid characters' };
  }
  return { value: trimmed, error: null };
}

export function jsonString(value: string): string {
  let out = '"';
  for (const char of value) {
    const code = char.codePointAt(0) ?? 0;
    if (char === '"') out += '\\"';
    else if (char === '\\') out += '\\\\';
    else if (char === '\b') out += '\\b';
    else if (char === '\f') out += '\\f';
    else if (char === '\n') out += '\\n';
    else if (char === '\r') out += '\\r';
    else if (char === '\t') out += '\\t';
    else if (code < 32) out += `\\u${code.toString(16).padStart(4, '0')}`;
    else out += char;
  }
  return out + '"';
}

export function canonicalPaymentIntentJSON(fields: {
  amountMinor: number;
  bank: string;
  consentSummary: string;
  feeMinor: number;
  localReference: string;
  method: string;
  provider: string;
  quoteExpiresAt: string;
  quoteId: string;
  recipientId: string;
  recipientName: string;
}): string {
  const pairs: [string, string][] = [
    ['amountMinor', String(fields.amountMinor)],
    ['bank', jsonString(fields.bank)],
    ['consentAccepted', 'true'],
    ['consentSummary', jsonString(fields.consentSummary)],
    ['currency', jsonString('GBP')],
    ['feeMinor', String(fields.feeMinor)],
    ['localReference', jsonString(fields.localReference)],
    ['method', jsonString(fields.method)],
    ['provider', jsonString(fields.provider)],
    ['quoteExpiresAt', jsonString(fields.quoteExpiresAt)],
    ['quoteId', jsonString(fields.quoteId)],
    ['recipientId', jsonString(fields.recipientId)],
    ['recipientName', jsonString(fields.recipientName)],
  ];
  return `{${pairs.map(([key, value]) => `${jsonString(key)}:${value}`).join(',')}}`;
}

export function sha256Hex(text: string): string {
  const bytes = new TextEncoder().encode(text);
  const bitLength = BigInt(bytes.length) * 8n;
  const padded = Array.from(bytes);
  padded.push(0x80);
  while (padded.length % 64 !== 56) padded.push(0);
  for (let shift = 56; shift >= 0; shift -= 8) {
    padded.push(Number((bitLength >> BigInt(shift)) & 0xffn));
  }
  const k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  const rotr = (x: number, n: number) => ((x >>> n) | (x << (32 - n))) >>> 0;
  let h = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];
  for (let offset = 0; offset < padded.length; offset += 64) {
    const w = new Array<number>(64);
    for (let i = 0; i < 16; i++) {
      const j = offset + i * 4;
      w[i] = ((padded[j] << 24) | (padded[j + 1] << 16) | (padded[j + 2] << 8) | padded[j + 3]) >>> 0;
    }
    for (let i = 16; i < 64; i++) {
      const s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      const s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }
    let a = h[0],
      b = h[1],
      c = h[2],
      d = h[3],
      e = h[4],
      f = h[5],
      g = h[6],
      hh = h[7];
    for (let i = 0; i < 64; i++) {
      const s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const ch = (e & f) ^ (~e & g);
      const t1 = (hh + s1 + ch + k[i] + w[i]) >>> 0;
      const s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const t2 = (s0 + maj) >>> 0;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) >>> 0;
    }
    h = [a, b, c, d, e, f, g, hh].map((value, index) => (value + h[index]) >>> 0);
  }
  return h.map((value) => value.toString(16).padStart(8, '0')).join('');
}

export function classifyPaymentIntent(
  statusCode: number,
  body: PaymentIntentResponseBody,
): IntentDisposition {
  const normalized = body.status?.trim().toLowerCase().replaceAll('-', '_');
  if (normalized === 'succeeded' || normalized === 'success' || normalized === 'completed')
    return 'succeeded';
  if (normalized === 'declined' || normalized === 'decline') return 'declined';
  if (normalized === 'action_required' || normalized === 'requires_action') return 'actionRequired';
  const code = body.code?.trim().toUpperCase();
  if (code === 'SUCCEEDED' || code === 'SUCCESS') return 'succeeded';
  if (code === 'DECLINED') return 'declined';
  if (code === 'ACTION_REQUIRED' || code === 'REQUIRES_ACTION') return 'actionRequired';
  if (statusCode === 422) return 'declined';
  if (statusCode === 202) return 'actionRequired';
  if (statusCode >= 200 && statusCode < 300 && body.ok) return 'succeeded';
  return 'retrySameIntent';
}

export function paymentIntentMessage(disposition: IntentDisposition, error?: string): string {
  const reason = error?.trim() ?? '';
  if (disposition === 'succeeded')
    return 'Payment intent succeeded. This intent was not submitted again.';
  const lead = reason.replace(/\.+$/, '');
  if (disposition === 'declined')
    return `${lead || 'Payment declined'}. This intent stays closed.`;
  if (disposition === 'actionRequired')
    return `${lead || 'Action required'}. This intent was not recreated.`;
  return `${lead || 'Outcome may be unknown'}. Retry keeps the same idempotency key and payload hash.`;
}

export function preparePaymentIntent(input: {
  recipientId: string;
  recipientName: string;
  recipientDetail: string;
  amountInput: string;
  localReference: string;
  method: IntentMethod;
  now?: Date;
  ttlSeconds?: number;
  idempotencyKey?: string;
  quoteId?: string;
  quoteExpiresAt?: string;
}): PaymentIntentAttempt {
  const recipient = input.recipientId.trim();
  const name = localizedRecipientName(input.recipientName);
  if (!recipient || !name) throw new PaymentIntentError('Recipient is required', 'validation');
  const amountMinor = parsePence(input.amountInput);
  if (amountMinor === null)
    throw new PaymentIntentError(
      'Enter an amount from £0.01 to £10,000 with no more than two decimals.',
      'validation',
    );
  const reference = normalizedLocalReference(input.localReference);
  if (!reference.value) throw new PaymentIntentError(reference.error || 'Local reference is required', 'validation');
  const idempotencyKey = input.idempotencyKey ?? crypto.randomUUID();
  const quoteId = input.quoteId ?? `quote-${crypto.randomUUID()}`;
  if (!safeToken.test(idempotencyKey))
    throw new PaymentIntentError('Idempotency key is invalid', 'validation');
  if (!safeToken.test(quoteId)) throw new PaymentIntentError('Quote id is invalid', 'validation');
  const now = input.now ?? new Date();
  const expiry =
    input.quoteExpiresAt ??
    formatUTC(new Date(now.getTime() + (input.ttlSeconds ?? paymentQuoteTTLSeconds) * 1000));
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(expiry))
    throw new PaymentIntentError('Quote expiry is invalid', 'validation');
  const feeMinor = rehearsalFeeMinor(input.method, amountMinor);
  const bank = baselineBank(input.method);
  const canonicalBody = canonicalPaymentIntentJSON({
    amountMinor,
    bank,
    consentSummary: paymentConsentSummary,
    feeMinor,
    localReference: reference.value,
    method: input.method,
    provider: baselineProviderId(input.method),
    quoteExpiresAt: expiry,
    quoteId,
    recipientId: recipient,
    recipientName: name,
  });
  return new PaymentIntentAttempt({
    idempotencyKey,
    payloadHash: sha256Hex(canonicalBody),
    canonicalBody,
    quoteExpiresAt: expiry,
    review: {
      recipientName: name,
      recipientDetail: input.recipientDetail.trim(),
      amountMinor,
      feeMinor,
      amountLabel: money(amountMinor),
      feeLabel: money(feeMinor),
      methodLabel: baselineMethodLabel(input.method),
      bank,
      quoteExpiresAt: expiry,
      expiryLabel: localizedQuoteExpiry(expiry),
      consentSummary: paymentConsentSummary,
      localReference: reference.value,
      currency: 'GBP',
    },
  });
}

export class PaymentIntentAttempt {
  readonly idempotencyKey: string;
  readonly payloadHash: string;
  readonly canonicalBody: string;
  readonly quoteExpiresAt: string;
  readonly review: PaymentReview;
  private inFlight = false;
  private submitted = false;
  settledSubmission: PaymentIntentSubmission | null = null;

  constructor(prepared: {
    idempotencyKey: string;
    payloadHash: string;
    canonicalBody: string;
    quoteExpiresAt: string;
    review: PaymentReview;
  }) {
    this.idempotencyKey = prepared.idempotencyKey;
    this.payloadHash = prepared.payloadHash;
    this.canonicalBody = prepared.canonicalBody;
    this.quoteExpiresAt = prepared.quoteExpiresAt;
    this.review = prepared.review;
  }

  hasSubmitted(): boolean {
    return this.submitted || this.settledSubmission !== null;
  }

  async submit(
    now: Date,
    consentAccepted: boolean,
    transport: (
      canonicalBody: string,
      idempotencyKey: string,
      payloadHash: string,
    ) => Promise<PaymentIntentHttpResult>,
  ): Promise<PaymentIntentSubmission> {
    if (this.settledSubmission) return this.settledSubmission;
    if (this.inFlight) throw new PaymentIntentError('Payment is already being submitted.', 'duplicate');
    if (!this.submitted) {
      if (!consentAccepted) throw new PaymentIntentError('Consent is required', 'validation');
      if (isQuoteExpired(this.quoteExpiresAt, now)) {
        throw new PaymentIntentError('Quote expired. Refresh the quote before confirming.', 'quote_expired');
      }
    }
    this.inFlight = true;
    this.submitted = true;
    try {
      const http = await transport(this.canonicalBody, this.idempotencyKey, this.payloadHash);
      const disposition = classifyPaymentIntent(http.statusCode, http.body);
      const intentId = http.body.intentId || http.body.intent_id;
      const submission: PaymentIntentSubmission = {
        disposition,
        statusCode: http.statusCode,
        intentId,
        ok: Boolean(http.body.ok),
        code: http.body.code,
        error: http.body.error,
        message: paymentIntentMessage(disposition, http.body.error),
        idempotencyKey: this.idempotencyKey,
        payloadHash: this.payloadHash,
        body: http.body,
        terminal: disposition === 'succeeded' || disposition === 'declined' || disposition === 'actionRequired',
      };
      if (submission.terminal) this.settledSubmission = submission;
      return submission;
    } finally {
      this.inFlight = false;
    }
  }
}
