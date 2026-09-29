export const GATEWAY_MAX_ATTEMPTS = 3;
export const GATEWAY_INITIAL_BACKOFF_MS = 200;
export const GATEWAY_MAX_BACKOFF_MS = 1600;

const UUID_V4 =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type PaymentMethodName = 'card' | 'bank';

export type PaymentAttempt = {
  idempotencyKey: string;
  method: PaymentMethodName;
  sessionId: string;
};

/** UUID version 4 idempotency key for one payment attempt. */
export function newPaymentIdempotencyKey(): string {
  return crypto.randomUUID();
}

export function isUuidV4(value: string): boolean {
  return UUID_V4.test(value);
}

export function isGatewayTimeoutStatus(status: number | undefined): boolean {
  return status === 502 || status === 504;
}

/**
 * Exponential backoff with jitter for gateway timeouts.
 * retryIndex 0 is the wait before the second attempt.
 */
export function backoffMillis(
  retryIndex: number,
  randomUnit = 0,
  initialMs = GATEWAY_INITIAL_BACKOFF_MS,
  maxMs = GATEWAY_MAX_BACKOFF_MS,
): number {
  let delay = initialMs;
  for (let index = 0; index < retryIndex; index += 1) {
    delay = Math.min(delay * 2, maxMs);
  }
  const jitter = Math.floor(Math.min(1, Math.max(0, randomUnit)) * (initialMs / 2));
  return delay + jitter;
}

/**
 * Submits one GBP payment. HTTP 502 and 504 retry with exponential backoff.
 * The rehearsal session, idempotency key, and method stay on the original attempt.
 */
export async function orchestratePayment<T>(options: {
  idempotencyKey: string;
  method: PaymentMethodName;
  sessionId: string;
  post: (attempt: PaymentAttempt) => Promise<T>;
  maxAttempts?: number;
  initialBackoffMs?: number;
  sleep?: (ms: number) => Promise<void>;
  random?: () => number;
  onRetry?: (attemptNumber: number, status: number) => void;
}): Promise<T> {
  const {
    idempotencyKey,
    method,
    sessionId,
    post,
    maxAttempts = GATEWAY_MAX_ATTEMPTS,
    initialBackoffMs = GATEWAY_INITIAL_BACKOFF_MS,
    sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    random = Math.random,
    onRetry,
  } = options;

  if (!isUuidV4(idempotencyKey)) {
    throw new Error('Idempotency key must be a UUID v4');
  }
  if (!/^[A-Za-z0-9_-]{3,64}$/.test(sessionId)) {
    throw new Error('Session ID is required');
  }

  let attempt = 1;
  while (true) {
    try {
      return await post({ idempotencyKey, method, sessionId });
    } catch (error) {
      const status = statusOf(error);
      if (!isGatewayTimeoutStatus(status) || attempt >= maxAttempts) {
        if (isGatewayTimeoutStatus(status)) {
          throw new Error(
            'Gateway timed out. Retry keeps this payment on the same method and the same key.',
          );
        }
        throw error;
      }
      onRetry?.(attempt + 1, status as number);
      await sleep(backoffMillis(attempt - 1, random(), initialBackoffMs));
      attempt += 1;
    }
  }
}

function statusOf(error: unknown): number | undefined {
  if (!error || typeof error !== 'object' || !('status' in error)) return undefined;
  const status = (error as { status?: unknown }).status;
  return typeof status === 'number' ? status : undefined;
}
