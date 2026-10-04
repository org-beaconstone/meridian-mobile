export type PayMethod = 'card' | 'bank';

export function backoffDelayMs(failedAttempt: number, initial = 200, cap = 1600, jitter = 0): number {
  const exponent = Math.min(8, Math.max(0, failedAttempt - 1));
  let scaled = initial;
  for (let step = 0; step < exponent; step += 1) {
    if (scaled > cap) return cap + jitter;
    scaled *= 2;
  }
  return Math.min(scaled, cap) + jitter;
}

export function isGatewayRetryStatus(status: number): boolean {
  return status === 502 || status === 504;
}

export interface RailHealth {
  method: string;
  provider: string;
  status: string;
}

export interface CorridorHealth {
  id?: string;
  status?: string;
  currency?: string;
  rails?: RailHealth[];
}

export interface SessionHealth {
  status?: string;
  simulation?: boolean;
  corridors?: CorridorHealth[];
}

export type CorridorNotice =
  | {
      type: 'switch';
      corridorId: string;
      selected: PayMethod;
      alternate: PayMethod;
      reason: 'degraded' | 'outage';
    }
  | { type: 'unavailable'; corridorId: string; message: string };

export type AttemptOutcome<T> =
  | { type: 'success'; value: T }
  | { type: 'retry'; status: number }
  | { type: 'stop'; error: Error };

export function railLabel(method: PayMethod): string {
  return method === 'card' ? 'Debit card · Adyen' : 'Bank payment · Worldpay';
}

export function parseSessionHealth(value: unknown): SessionHealth | null {
  if (!value || typeof value !== 'object') return null;
  const record = value as SessionHealth;
  if (record.corridors !== undefined && !Array.isArray(record.corridors)) return null;
  return record;
}

export function corridorNotice(health: SessionHealth | null, selected: PayMethod): CorridorNotice | null {
  if (!health) return null;
  const corridor = (health.corridors ?? []).find((item) => {
    const currency = item.currency?.toUpperCase();
    const id = item.id?.toUpperCase();
    return currency === 'GBP' || id === 'GB' || id === 'GBP';
  });
  if (!corridor) return null;
  const baseline = (corridor.rails ?? []).filter(isBaselineRail);
  const selectedRail = baseline.find((rail) => rail.method.toLowerCase() === selected);
  const corridorStatus = normalizeStatus(corridor.status);
  const selectedStatus = selectedRail
    ? normalizeStatus(selectedRail.status)
    : corridorStatus === 'outage'
      ? 'outage'
      : 'healthy';
  if (selectedStatus !== 'degraded' && selectedStatus !== 'outage') return null;
  const alternate = baseline.find(
    (rail) => rail.method.toLowerCase() !== selected && normalizeStatus(rail.status) === 'healthy',
  );
  const corridorId = corridor.id || 'GB';
  if (alternate && (alternate.method.toLowerCase() === 'card' || alternate.method.toLowerCase() === 'bank')) {
    return {
      type: 'switch',
      corridorId,
      selected,
      alternate: alternate.method.toLowerCase() as PayMethod,
      reason: selectedStatus,
    };
  }
  return {
    type: 'unavailable',
    corridorId,
    message: `Corridor ${corridorId} is unavailable. No other rehearsed rail is healthy. Your payment details are unchanged.`,
  };
}

export async function runGatewayRetries<T>(
  perform: () => Promise<AttemptOutcome<T>>,
  options?: {
    maxAttempts?: number;
    sleep?: (ms: number) => Promise<void>;
    delay?: (failedAttempt: number) => number;
  },
): Promise<T> {
  const maxAttempts = options?.maxAttempts ?? 3;
  const sleep = options?.sleep ?? ((ms: number) => new Promise((resolve) => setTimeout(resolve, ms)));
  const delay = options?.delay ?? ((failedAttempt: number) => backoffDelayMs(failedAttempt));
  let lastStatus = 0;
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const outcome = await perform();
    if (outcome.type === 'success') return outcome.value;
    if (outcome.type === 'stop') throw outcome.error;
    lastStatus = outcome.status;
    if (attempt === maxAttempts) break;
    await sleep(delay(attempt));
  }
  const exhausted = new Error(
    `Gateway HTTP ${lastStatus} after ${maxAttempts} attempts. Your payment details are unchanged. Retry uses the same payment key.`,
  );
  exhausted.name = 'RetriesExhausted';
  throw exhausted;
}

function isBaselineRail(rail: RailHealth): boolean {
  const method = rail.method.toLowerCase();
  const provider = rail.provider.toLowerCase();
  return (method === 'card' && provider === 'adyen') || (method === 'bank' && provider === 'worldpay');
}

function normalizeStatus(raw: string | undefined): string {
  switch ((raw ?? '').toLowerCase()) {
    case 'healthy':
    case 'up':
    case 'ok':
    case 'available':
      return 'healthy';
    case 'degraded':
    case 'degradation':
      return 'degraded';
    case 'outage':
    case 'down':
    case 'unavailable':
      return 'outage';
    default:
      return 'unknown';
  }
}
