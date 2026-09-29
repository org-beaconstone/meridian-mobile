/**
 * Browser companion telemetry for the rehearsal UI.
 * This is not the native Swift or Kotlin SDK. It mirrors W3C traceparent
 * propagation, span timers, and PAN/IBAN redaction against the same Java API.
 */

export type SpanRecord = {
  name: string;
  traceId: string;
  spanId: string;
  parentSpanId?: string;
  durationMillis: number;
  status: string;
  attributes: Record<string, string>;
};

export type TelemetryEvent = {
  name: string;
  code: string;
  stage: string;
  message: string;
  traceId: string;
  spanId: string;
  attributes: Record<string, string>;
};

export type Corridor = { id: string; state: string };
export type HealthReading = { connection: string; corridors: Corridor[] };
export type HealthMemory = {
  connection: string | null;
  corridors: Record<string, string>;
  lastError: string | null;
};

const spans: SpanRecord[] = [];
const events: TelemetryEvent[] = [];
const forbidden = new Set([
  'pan',
  'iban',
  'card',
  'cardnumber',
  'accountnumber',
  'cvv',
  'cvc',
  'note',
  'detail',
  'recipientdetail',
]);

export function resetTelemetry() {
  spans.length = 0;
  events.length = 0;
}

export function recordedSpans(): SpanRecord[] {
  return spans.map((span) => ({ ...span, attributes: { ...span.attributes } }));
}

export function recordedEvents(): TelemetryEvent[] {
  return events.map((event) => ({ ...event, attributes: { ...event.attributes } }));
}

function hex(numBytes: number): string {
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const bytes = new Uint8Array(numBytes);
    crypto.getRandomValues(bytes);
    const encoded = Array.from(bytes, (value) => value.toString(16).padStart(2, '0')).join('');
    if ([...encoded].some((character) => character !== '0')) return encoded;
  }
  return `${'0'.repeat(numBytes * 2 - 1)}1`;
}

export function isTraceparent(value: string): boolean {
  return /^00-[0-9a-f]{32}-[0-9a-f]{16}-01$/.test(value);
}

export type OpenSpan = {
  name: string;
  traceId: string;
  spanId: string;
  traceparent: string;
  end: (status: string, attributes?: Record<string, string>) => void;
};

export function openSpan(name: string, traceId = hex(16), parentSpanId?: string): OpenSpan {
  const spanId = hex(8);
  const started = typeof performance === 'undefined' ? Date.now() : performance.now();
  return {
    name,
    traceId,
    spanId,
    traceparent: `00-${traceId}-${spanId}-01`,
    end(status, attributes = {}) {
      const finished = typeof performance === 'undefined' ? Date.now() : performance.now();
      spans.push({
        name,
        traceId,
        spanId,
        parentSpanId,
        durationMillis: Math.max(0, Math.round(finished - started)),
        status,
        attributes: cleanAttributes(attributes),
      });
    },
  };
}

export function spanNameFor(path: string): string {
  if (path === '/payments') return 'payment.gateway';
  if (path === '/catalog') return 'http.catalog';
  if (path === '/session/health') return 'session.health';
  return 'http.client';
}

export function luhn(digits: string): boolean {
  if (!/^\d+$/.test(digits)) return false;
  let sum = 0;
  let alternate = false;
  for (let index = digits.length - 1; index >= 0; index -= 1) {
    let current = Number(digits[index]);
    if (alternate) {
      current *= 2;
      if (current > 9) current -= 9;
    }
    sum += current;
    alternate = !alternate;
  }
  return sum % 10 === 0;
}

export function isIban(candidate: string): boolean {
  const compact = candidate.replace(/ /g, '').toUpperCase();
  if (compact.length < 15 || compact.length > 34) return false;
  if (!/^[A-Z]{2}\d{2}[A-Z0-9]+$/.test(compact)) return false;
  const rearranged = compact.slice(4) + compact.slice(0, 4);
  let numeric = '';
  for (const character of rearranged) {
    const code = character.charCodeAt(0);
    if (code >= 48 && code <= 57) numeric += character;
    else if (code >= 65 && code <= 90) numeric += String(code - 55);
    else return false;
  }
  let remainder = 0;
  for (const character of numeric) remainder = (remainder * 10 + Number(character)) % 97;
  return remainder === 1;
}

export function sanitize(input: string): string {
  if (!input) return input;
  return scrubIbans(input).replace(/(?<![0-9])(?:\d[ -]?){12,18}\d(?![0-9])/g, (match) => {
    const digits = match.replace(/\D/g, '');
    return digits.length >= 13 && digits.length <= 19 && luhn(digits) ? '[REDACTED_PAN]' : match;
  });
}

function scrubIbans(input: string): string {
  const prefix = /(?<![A-Za-z0-9])[A-Z]{2}\d{2}/gi;
  let result = '';
  let index = 0;
  for (const match of input.matchAll(prefix)) {
    const start = match.index ?? 0;
    if (start < index) continue;
    result += input.slice(index, start);
    let cursor = start + match[0].length;
    let accepted = -1;
    while (cursor <= input.length) {
      const candidate = input.slice(start, cursor);
      const compactLength = candidate.replace(/\s/g, '').length;
      if (compactLength >= 15 && isIban(candidate)) accepted = cursor;
      if (cursor === input.length || compactLength >= 34) break;
      const next = input[cursor];
      if (next === ' ') {
        const following = input[cursor + 1];
        if (following && /[A-Za-z0-9]/.test(following)) {
          cursor += 1;
          continue;
        }
        break;
      }
      if (!/[A-Za-z0-9]/.test(next)) break;
      cursor += 1;
    }
    if (accepted > start) {
      result += '[REDACTED_IBAN]';
      index = accepted;
    } else {
      result += match[0];
      index = start + match[0].length;
    }
  }
  return result + input.slice(index);
}

export function cleanAttributes(input: Record<string, string>): Record<string, string> {
  const cleaned: Record<string, string> = {};
  for (const [key, value] of Object.entries(input)) {
    const normalized = key.toLowerCase().replace(/[_-]/g, '');
    if (forbidden.has(normalized) || normalized.includes('pan') || normalized.includes('iban')) continue;
    cleaned[key] = sanitize(value).slice(0, 180);
  }
  return cleaned;
}

export function recordEvent(event: TelemetryEvent) {
  events.push({
    ...event,
    code: sanitize(event.code).slice(0, 80),
    message: sanitize(event.message).slice(0, 180),
    attributes: cleanAttributes(event.attributes),
  });
}

export function recordError(input: {
  code: string;
  stage: string;
  message: string;
  traceId: string;
  spanId: string;
  attributes?: Record<string, string>;
}) {
  recordEvent({
    name: 'client.error',
    code: input.code,
    stage: input.stage,
    message: input.message,
    traceId: input.traceId,
    spanId: input.spanId,
    attributes: input.attributes ?? {},
  });
}

export function resolveBiometric(sensorAvailable: boolean): { outcome: string; code: string | null } {
  const span = openSpan('biometric.prompt');
  const outcome = sensorAvailable ? 'authenticated' : 'fallback';
  if (!sensorAvailable) {
    recordError({
      code: 'SCA_FALLBACK',
      stage: 'biometric',
      message: 'Local biometric sensor unavailable',
      traceId: span.traceId,
      spanId: span.spanId,
      attributes: { outcome },
    });
  }
  span.end(sensorAvailable ? 'ok' : 'error', { outcome });
  return { outcome, code: sensorAvailable ? null : 'SCA_FALLBACK' };
}

const cardIds = new Set(['adyen', 'card', 'adyen-card']);
const bankIds = new Set(['worldpay', 'bank', 'worldpay-bank']);

export function canonicalCorridor(id?: string, provider?: string): string {
  const candidates = [id, provider]
    .filter((value): value is string => typeof value === 'string')
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean);
  if (candidates.some((value) => bankIds.has(value))) return 'worldpay-bank';
  if (candidates.some((value) => cardIds.has(value))) return 'adyen-card';
  return 'corridor';
}

export function canonicalState(state?: string, status?: string): string {
  const raw = (state ?? status ?? 'unknown').trim().toLowerCase();
  if (raw === 'healthy' || raw === 'ok' || raw === 'up') return 'healthy';
  if (raw === 'degraded' || raw === 'impaired') return 'degraded';
  if (raw === 'down' || raw === 'unavailable' || raw === 'failed') return 'down';
  return 'unknown';
}

export function deriveConnection(explicit: unknown, status: unknown, corridors: Corridor[]): string {
  const normalized = typeof explicit === 'string' ? explicit.trim().toLowerCase() : '';
  const degraded = corridors.some((corridor) => corridor.state === 'degraded' || corridor.state === 'down');
  if (normalized === 'disconnected' || normalized === 'down') return 'disconnected';
  if (normalized === 'degraded' || degraded) return 'degraded';
  if (normalized === 'connected' || normalized === 'up') return 'connected';
  const service = typeof status === 'string' ? status.trim().toUpperCase() : '';
  if (service === 'DOWN' || service === 'UNAVAILABLE') return 'disconnected';
  return 'connected';
}

export function interpretSessionHealth(
  statusCode: number,
  body: string,
): { reading: HealthReading; errorCode?: string; errorMessage?: string } {
  if (statusCode < 200 || statusCode >= 300) {
    return {
      reading: { connection: 'disconnected', corridors: [] },
      errorCode: `HTTP_${statusCode}`,
      errorMessage: sanitize(body).slice(0, 180),
    };
  }
  try {
    const parsed = JSON.parse(body) as {
      status?: unknown;
      connection?: unknown;
      corridors?: unknown;
    };
    const corridors = Array.isArray(parsed.corridors)
      ? parsed.corridors.map((value) => {
          const corridor = value as { id?: string; provider?: string; state?: string; status?: string };
          return {
            id: canonicalCorridor(corridor.id, corridor.provider),
            state: canonicalState(corridor.state, corridor.status),
          };
        })
      : [];
    return { reading: { connection: deriveConnection(parsed.connection, parsed.status, corridors), corridors } };
  } catch (error) {
    return {
      reading: { connection: 'disconnected', corridors: [] },
      errorCode: 'DECODING_ERROR',
      errorMessage: sanitize(error instanceof Error ? error.message : 'Failed to parse session health'),
    };
  }
}

export function reduceHealth(
  previous: HealthMemory,
  reading: HealthReading,
  error?: { code: string; message: string },
): { memory: HealthMemory; events: TelemetryEvent[] } {
  const pending: TelemetryEvent[] = [];
  const traceId = hex(16);
  const spanId = hex(8);
  if (previous.connection !== reading.connection) {
    pending.push({
      name: 'connection.state',
      code: reading.connection.toUpperCase(),
      stage: 'health',
      message: `Connection ${reading.connection}`,
      traceId,
      spanId,
      attributes: { previous: previous.connection ?? 'unknown', connection: reading.connection },
    });
  }
  if (error && error.code !== previous.lastError) {
    pending.push({
      name: 'client.error',
      code: error.code,
      stage: 'health',
      message: error.message,
      traceId,
      spanId,
      attributes: { connection: reading.connection },
    });
  }
  const corridors = { ...previous.corridors };
  for (const corridor of reading.corridors) {
    const prior = corridors[corridor.id];
    if ((corridor.state === 'degraded' || corridor.state === 'down') && prior !== corridor.state) {
      pending.push({
        name: 'corridor.degraded',
        code: 'CORRIDOR_DEGRADED',
        stage: 'health',
        message: `${corridor.id} ${corridor.state}`,
        traceId,
        spanId,
        attributes: { corridorId: corridor.id, state: corridor.state },
      });
    }
    corridors[corridor.id] = corridor.state;
  }
  pending.forEach(recordEvent);
  return {
    memory: {
      connection: reading.connection,
      corridors,
      lastError: error?.code ?? null,
    },
    events: pending,
  };
}

export function healthSummary(reading: HealthReading): string {
  const degraded = reading.corridors.filter((corridor) => corridor.state === 'degraded' || corridor.state === 'down');
  if (degraded.length === 0) return `Session health: ${reading.connection}`;
  return `Session health: ${reading.connection} · ${degraded.map((corridor) => `${corridor.id} ${corridor.state}`).join(', ')}`;
}

export async function probeSessionHealth(
  room: string,
  fetchImpl: typeof fetch = fetch,
): Promise<{ reading: HealthReading; errorCode?: string; errorMessage?: string }> {
  const span = openSpan('session.health');
  try {
    const response = await fetchImpl('/api/v1/session/health', {
      headers: {
        'X-Rehearsal-Session': room,
        traceparent: span.traceparent,
      },
      signal: AbortSignal.timeout(15000),
    });
    const text = await response.text();
    const interpreted = interpretSessionHealth(response.status, text);
    span.end(interpreted.reading.connection === 'disconnected' ? 'error' : 'ok', {
      'http.status': String(response.status),
      'http.path': '/session/health',
    });
    return interpreted;
  } catch (error) {
    span.end('error', { 'http.path': '/session/health' });
    return {
      reading: { connection: 'disconnected', corridors: [] },
      errorCode: 'NETWORK_ERROR',
      errorMessage: sanitize(error instanceof Error ? error.message : 'Connection failed'),
    };
  }
}

export const emptyHealthMemory = (): HealthMemory => ({ connection: null, corridors: {}, lastError: null });
