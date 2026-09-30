export type IntentPhase = 'processing' | 'pending' | 'unknown' | 'succeeded' | 'declined';

export type ReceiptTransaction = {
  id: string;
  name: string;
  amount: number;
  date: string;
  category: string;
  status: string;
  provider: string;
  reference: string;
  method?: string;
  note?: string;
  recipientId?: string;
};

export type PaymentIntent = {
  id: string;
  status: string;
  amountMinor: number | null;
  currency: string | null;
  recipientId: string | null;
  recipientName: string | null;
  method: string | null;
  provider: string | null;
  note: string | null;
  supportReference: string | null;
  transaction: ReceiptTransaction | null;
  error: string | null;
  code: string | null;
};

export type IntentSnapshot = {
  intentId: string | null;
  sessionId: string;
  baseURL: string;
  idempotencyKey: string;
  recipientId: string;
  recipientName: string;
  amountMinor: number;
  method: 'card' | 'bank';
  note: string;
  phase: IntentPhase;
  supportReference: string | null;
  transaction: ReceiptTransaction | null;
  provider: string | null;
  detail: string | null;
  updatedAt: string;
};

export type RecoveryAction =
  | { kind: 'poll'; intentId: string }
  | { kind: 'showReceipt' }
  | { kind: 'showDecline' }
  | { kind: 'holdUnknown' };

export type StatusPollResult = {
  phase: IntentPhase;
  intent: PaymentIntent | null;
  attempts: number;
};

export const STATUS_BACKOFF = {
  initialMs: 500,
  maxMs: 4_000,
  maxAttempts: 5,
  maxElapsedMs: 15_000,
};

const STORAGE_KEY = 'meridian.intentSnapshots.v1';

export function classifyIntentStatus(raw: string | null | undefined): IntentPhase {
  const value = (raw ?? '').trim().toLowerCase().replaceAll('_', '-');
  switch (value) {
    case 'processing':
    case 'submitting':
    case 'prepared':
    case 'created':
    case 'in-progress':
    case 'authorizing':
      return 'processing';
    case 'pending':
    case 'payment-pending':
    case 'requires-action':
      return 'pending';
    case 'succeeded':
    case 'success':
    case 'completed':
    case 'complete':
      return 'succeeded';
    case 'declined':
    case 'declined-final':
    case 'payment-declined':
    case 'hard-decline':
      return 'declined';
    default:
      return 'unknown';
  }
}

export function phaseFromPaymentResult(result: { ok?: boolean; code?: string | null }): IntentPhase {
  if (result.ok) return 'succeeded';
  switch (result.code) {
    case 'PAYMENT_DECLINED':
      return 'declined';
    case 'PAYMENT_PENDING':
      return 'pending';
    case 'PAYMENT_PROCESSING':
      return 'processing';
    default:
      return 'unknown';
  }
}

export function presentationPhase(intent: PaymentIntent): IntentPhase {
  const currency = intent.currency?.trim();
  const classified = classifyIntentStatus(intent.status);
  if (currency && currency.toUpperCase() !== 'GBP' && classified !== 'declined') return 'unknown';
  return classified;
}

export function recoveryAction(snapshot: IntentSnapshot): RecoveryAction {
  if (snapshot.phase === 'succeeded') return { kind: 'showReceipt' };
  if (snapshot.phase === 'declined') return { kind: 'showDecline' };
  if (snapshot.intentId) return { kind: 'poll', intentId: snapshot.intentId };
  return { kind: 'holdUnknown' };
}

export function recoveryFeedback(phase: IntentPhase): string {
  switch (phase) {
    case 'succeeded':
      return 'Payment complete.';
    case 'declined':
      return 'This payment was declined. No money was taken. It will not be submitted again automatically.';
    case 'pending':
      return 'This payment is pending confirmation. Status checks continue without submitting it again.';
    case 'processing':
      return 'Checking payment status. This does not start a new payment.';
    case 'unknown':
      return 'The payment status is still unknown. Status checks resume after a restart. A new payment was not created.';
  }
}

export function providerLabel(provider: string | null | undefined): string {
  if (provider === 'adyen') return 'Adyen';
  if (provider === 'worldpay') return 'Worldpay';
  return 'Simulated provider';
}

export function baselineProvider(method: string): string {
  return method === 'bank' ? 'worldpay' : 'adyen';
}

/** Equal-jitter delay capped at maxMs. Never exceeds the cap. */
export function backoffMillis(
  attemptIndex: number,
  randomUnit: number,
  initialMs = STATUS_BACKOFF.initialMs,
  maxMs = STATUS_BACKOFF.maxMs,
): number {
  if (attemptIndex < 0) throw new Error('attemptIndex must be >= 0');
  let delay = initialMs;
  let steps = attemptIndex;
  while (steps > 0) {
    if (delay >= maxMs / 2) {
      delay = maxMs;
      break;
    }
    delay *= 2;
    steps -= 1;
  }
  if (delay > maxMs) delay = maxMs;
  const unit = Math.min(1, Math.max(0, randomUnit));
  const half = Math.floor(delay / 2);
  const jitter = Math.floor(unit * (delay - half));
  return half + jitter;
}

export function paymentIntentPath(id: string): string {
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(id)) throw new Error('Invalid payment intent id');
  return `/api/v2/payment-intents/${id}`;
}

export function resolvedSupportReference(
  snapshot: IntentSnapshot,
  intent: PaymentIntent | null,
): string {
  const explicit = intent?.supportReference?.trim();
  if (explicit) return explicit;
  const stored = snapshot.supportReference?.trim();
  if (stored) return stored;
  const reference = intent?.transaction?.reference || snapshot.transaction?.reference;
  if (reference) return reference;
  const id = intent?.id || snapshot.intentId || snapshot.idempotencyKey;
  return `MER-${id.slice(0, 8).toUpperCase()}`;
}

export function applying(result: StatusPollResult, snapshot: IntentSnapshot): IntentSnapshot {
  const intent = result.intent;
  const next: IntentSnapshot = {
    ...snapshot,
    intentId: intent?.id || snapshot.intentId,
    amountMinor: intent?.amountMinor ?? snapshot.amountMinor,
    recipientName: intent?.recipientName || snapshot.recipientName,
    recipientId: intent?.recipientId || snapshot.recipientId,
    method: intent?.method === 'bank' || intent?.method === 'card' ? intent.method : snapshot.method,
    note: intent?.note ?? snapshot.note,
    provider: intent?.provider || snapshot.provider,
    transaction: intent?.transaction ?? snapshot.transaction,
    supportReference: intent?.supportReference || snapshot.supportReference,
    phase: result.phase,
    detail: recoveryFeedback(result.phase),
    updatedAt: new Date().toISOString(),
  };
  return { ...next, supportReference: resolvedSupportReference(next, intent) };
}

export type PaymentReceipt = {
  recipientName: string;
  amountMinor: number;
  supportReference: string;
  transactionId: string | null;
  transactionDate: string | null;
  method: string | null;
  provider: string | null;
  note: string | null;
  status: string | null;
};

export function makeReceipt(snapshot: IntentSnapshot, intent: PaymentIntent | null = null): PaymentReceipt {
  const transaction = intent?.transaction ?? snapshot.transaction;
  return {
    recipientName: intent?.recipientName || snapshot.recipientName,
    amountMinor: intent?.amountMinor ?? transaction?.amount ?? snapshot.amountMinor,
    supportReference: resolvedSupportReference(snapshot, intent),
    transactionId: transaction?.id || intent?.id || snapshot.intentId,
    transactionDate: transaction?.date ?? null,
    method: transaction?.method || intent?.method || snapshot.method,
    provider: transaction?.provider || intent?.provider || snapshot.provider,
    note: transaction?.note || intent?.note || snapshot.note,
    status: transaction?.status || (snapshot.phase === 'succeeded' ? 'completed' : snapshot.phase),
  };
}

/**
 * GET /api/v2/payment-intents/{id} with bounded jittered backoff.
 * Does not submit a payment.
 */
export async function pollPaymentIntent(options: {
  intentId: string;
  fetchIntent: (id: string) => Promise<PaymentIntent>;
  sleep?: (ms: number) => Promise<void>;
  randomUnit?: () => number;
  maxAttempts?: number;
  initialBackoffMs?: number;
  maxBackoffMs?: number;
  maxElapsedMs?: number;
}): Promise<StatusPollResult> {
  const sleep = options.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
  const randomUnit = options.randomUnit ?? Math.random;
  const maxAttempts = options.maxAttempts ?? STATUS_BACKOFF.maxAttempts;
  const initialBackoffMs = options.initialBackoffMs ?? STATUS_BACKOFF.initialMs;
  const maxBackoffMs = options.maxBackoffMs ?? STATUS_BACKOFF.maxMs;
  const maxElapsedMs = options.maxElapsedMs ?? STATUS_BACKOFF.maxElapsedMs;
  let attempt = 0;
  let elapsed = 0;
  let last: PaymentIntent | null = null;
  while (attempt < maxAttempts) {
    attempt += 1;
    try {
      const intent = await options.fetchIntent(options.intentId);
      last = intent;
      const phase = presentationPhase(intent);
      if (phase === 'succeeded' || phase === 'declined') {
        return { phase, intent, attempts: attempt };
      }
    } catch {
      // A failed lookup stays unknown and does not create another payment.
    }
    if (attempt >= maxAttempts) break;
    const wait = backoffMillis(attempt - 1, randomUnit(), initialBackoffMs, maxBackoffMs);
    if (elapsed >= maxElapsedMs || wait > maxElapsedMs - elapsed) break;
    await sleep(wait);
    elapsed += wait;
  }
  const phase = last ? presentationPhase(last) : 'unknown';
  if (phase === 'succeeded' || phase === 'declined') return { phase, intent: last, attempts: attempt };
  return {
    phase: phase === 'pending' || phase === 'processing' ? phase : 'unknown',
    intent: last,
    attempts: attempt,
  };
}

export function normalizeIntent(value: unknown, fallbackId: string): PaymentIntent {
  const raw = (value ?? {}) as Record<string, unknown>;
  const transaction = raw.transaction as ReceiptTransaction | null | undefined;
  return {
    id: typeof raw.id === 'string' && raw.id ? raw.id : fallbackId,
    status: typeof raw.status === 'string' ? raw.status : typeof raw.phase === 'string' ? raw.phase : 'unknown',
    amountMinor: Number.isInteger(raw.amountMinor) ? (raw.amountMinor as number) : null,
    currency: typeof raw.currency === 'string' ? raw.currency : null,
    recipientId: typeof raw.recipientId === 'string' ? raw.recipientId : null,
    recipientName: typeof raw.recipientName === 'string' ? raw.recipientName : null,
    method: typeof raw.method === 'string' ? raw.method : null,
    provider: typeof raw.provider === 'string' ? raw.provider : null,
    note: typeof raw.note === 'string' ? raw.note : null,
    supportReference: typeof raw.supportReference === 'string' ? raw.supportReference : null,
    transaction: transaction && typeof transaction === 'object' ? transaction : null,
    error: typeof raw.error === 'string' ? raw.error : null,
    code: typeof raw.code === 'string' ? raw.code : null,
  };
}

export async function fetchPaymentIntent(
  room: string,
  id: string,
  fetchImpl: typeof fetch = fetch,
): Promise<PaymentIntent> {
  const path = paymentIntentPath(id);
  let response: Response;
  try {
    response = await fetchImpl(path, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
        'X-Rehearsal-Session': room,
      },
      signal: AbortSignal.timeout(15000),
    });
  } catch {
    throw new Error('Status lookup failed');
  }
  if (!response.ok && response.status !== 202) {
    throw new Error(`HTTP ${response.status}`);
  }
  return normalizeIntent(await response.json(), id);
}

function readStore(): Record<string, IntentSnapshot> {
  if (typeof localStorage === 'undefined') return {};
  try {
    const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}') as Record<string, IntentSnapshot>;
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    return {};
  }
}

export function loadSnapshot(sessionId: string): IntentSnapshot | null {
  return readStore()[sessionId] ?? null;
}

export function saveSnapshot(snapshot: IntentSnapshot) {
  if (typeof localStorage === 'undefined') return;
  const sessions = readStore();
  sessions[snapshot.sessionId] = snapshot;
  localStorage.setItem(STORAGE_KEY, JSON.stringify(sessions));
}

export function removeSnapshot(sessionId: string) {
  if (typeof localStorage === 'undefined') return;
  const sessions = readStore();
  delete sessions[sessionId];
  localStorage.setItem(STORAGE_KEY, JSON.stringify(sessions));
}

export function latestRecoverable(): IntentSnapshot | null {
  const sessions = Object.values(readStore());
  const open = sessions.filter((snapshot) => {
    const action = recoveryAction(snapshot);
    return action.kind === 'poll' || action.kind === 'holdUnknown';
  });
  const pool = open.length > 0 ? open : sessions;
  return pool.sort((a, b) => (a.updatedAt < b.updatedAt ? 1 : -1))[0] ?? null;
}
