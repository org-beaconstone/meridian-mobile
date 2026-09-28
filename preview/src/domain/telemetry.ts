/** Browser-companion telemetry. This is not the native SDK. */

const IBAN_COMPACT = /(?<![A-Za-z0-9])[A-Za-z]{2}[0-9]{2}[A-Za-z0-9]{11,30}(?![A-Za-z0-9])/gi;
const IBAN_GROUPED =
  /(?<![A-Za-z0-9])[A-Za-z]{2}[0-9]{2}(?:[ -][A-Za-z0-9]{4}){2,7}(?:[ -][A-Za-z0-9]{1,3})?(?![A-Za-z0-9])/gi;
const PAN = /(?<![0-9])(?:[0-9][ -]?){12,18}[0-9](?![0-9])/g;

export function redact(input: string): string {
  return input.replace(IBAN_GROUPED, '[REDACTED_IBAN]').replace(IBAN_COMPACT, '[REDACTED_IBAN]').replace(PAN, '[REDACTED_PAN]');
}

export function containsSensitive(input: string): boolean {
  return redact(input) !== input;
}

export function shouldInjectTraceparent(path: string): boolean {
  const bare = path.split('?')[0].replace(/\/$/, '');
  return bare.endsWith('/catalog') || bare.endsWith('/payments') || bare.endsWith('/session/health');
}

function hex(byteCount: number): string {
  const bytes = new Uint8Array(byteCount);
  crypto.getRandomValues(bytes);
  if (bytes.every((value) => value === 0)) bytes[0] = 1;
  return [...bytes].map((value) => value.toString(16).padStart(2, '0')).join('');
}

export function createTraceparent(): string {
  return `00-${hex(16)}-${hex(8)}-01`;
}

export function isValidTraceparent(value: string): boolean {
  const parts = value.split('-');
  if (parts.length !== 4) return false;
  const [version, trace, span, flags] = parts;
  if (version !== '00' || flags.length !== 2 || trace.length !== 32 || span.length !== 16) return false;
  if (/^0+$/.test(trace) || /^0+$/.test(span)) return false;
  return [trace, span, flags].every((part) => /^[0-9a-f]+$/.test(part));
}

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
  errorCode: string;
  failureStage: string;
  attributes: Record<string, string>;
};

export type CorridorHealth = {
  id: string;
  state: string;
  provider?: string;
  method?: string;
};

export type SessionHealthReport = {
  connectionState: string;
  httpStatus?: number;
  corridors: CorridorHealth[];
};

const allowed = new Set([
  'http.route',
  'http.method',
  'http.status_code',
  'payment.method',
  'payment.provider',
  'outcome',
  'corridor.id',
  'corridor.state',
  'connection.previous',
  'connection.current',
  'recipient.count',
  'provider.count',
  'duration_ms',
  'error.message',
]);

export function safeCode(code: string): string {
  const token = code.trim();
  if (!/^[A-Za-z0-9_]{1,64}$/.test(token) || containsSensitive(token)) return 'REDACTED_CODE';
  return token;
}

export function sanitizeAttributes(input: Record<string, string | undefined>): Record<string, string> {
  const output: Record<string, string> = {};
  for (const [key, raw] of Object.entries(input)) {
    if (!allowed.has(key) || raw == null) continue;
    const cleaned = clean(key, raw);
    if (cleaned) output[key] = cleaned;
  }
  return output;
}

function clean(key: string, value: string): string {
  if (key === 'payment.provider') return value === 'adyen' || value === 'worldpay' ? value : '';
  if (key === 'payment.method') return value === 'card' || value === 'bank' ? value : '';
  if (['http.status_code', 'recipient.count', 'provider.count', 'duration_ms'].includes(key)) {
    return /^[0-9]{1,12}$/.test(value) ? value : '';
  }
  if (key === 'http.method') return /^[A-Z]{1,8}$/.test(value) ? value : '';
  if (key === 'error.message') return redact(value).slice(0, 180);
  if (key === 'corridor.id') return value === 'adyen-card' || value === 'worldpay-bank' || value === 'session' ? value : '';
  if (['corridor.state', 'connection.previous', 'connection.current'].includes(key)) {
    const redacted = redact(value);
    return /^[a-z0-9_.:-]{1,64}$/.test(redacted) ? redacted : '';
  }
  if (key === 'outcome') {
    const redacted = redact(value);
    return /^[A-Za-z0-9_.:-]{1,64}$/.test(redacted) && !containsSensitive(redacted) ? redacted : '';
  }
  return redact(value).slice(0, 80);
}

function normalizeCorridor(row: Record<string, unknown>): CorridorHealth | null {
  const stateText = String(row.state ?? '').toLowerCase();
  const state =
    stateText === 'ok' || stateText === 'up' || stateText === 'healthy'
      ? 'healthy'
      : stateText === 'degraded' || stateText === 'warn' || stateText === 'warning'
        ? 'degraded'
        : stateText === 'down' || stateText === 'unavailable' || stateText === 'unreachable'
          ? 'down'
          : '';
  if (!state) return null;
  const provider = String(row.provider ?? '').toLowerCase();
  const method = String(row.method ?? '').toLowerCase();
  const id = String(row.id ?? '').toLowerCase();
  if (provider === 'adyen' && (method === '' || method === 'card')) {
    return { id: 'adyen-card', state, provider: 'adyen', method: 'card' };
  }
  if (provider === 'worldpay' && (method === '' || method === 'bank')) {
    return { id: 'worldpay-bank', state, provider: 'worldpay', method: 'bank' };
  }
  if (id === 'adyen-card') return { id, state, provider: 'adyen', method: 'card' };
  if (id === 'worldpay-bank') return { id, state, provider: 'worldpay', method: 'bank' };
  if (state === 'healthy') return null;
  return { id: 'session', state };
}

export function parseSessionHealth(statusCode: number, body: unknown): SessionHealthReport {
  if (statusCode === 0) return { connectionState: 'unreachable', corridors: [] };
  const json = body && typeof body === 'object' ? (body as Record<string, unknown>) : {};
  const status = String(json.status ?? '').toLowerCase();
  const rows = Array.isArray(json.corridors) ? json.corridors : [];
  const corridors = rows
    .map((row) => (row && typeof row === 'object' ? normalizeCorridor(row as Record<string, unknown>) : null))
    .filter((row): row is CorridorHealth => row != null);
  let connectionState = 'degraded';
  if (statusCode >= 500) connectionState = 'unreachable';
  else if (corridors.some((corridor) => corridor.state === 'down')) connectionState = 'unreachable';
  else if (corridors.some((corridor) => corridor.state === 'degraded')) connectionState = 'degraded';
  else if (status === 'up' || status === 'ok' || status === 'healthy') {
    connectionState = statusCode >= 400 ? 'degraded' : 'healthy';
  } else if (status === 'down' || status === 'unavailable' || status === 'unreachable') {
    connectionState = 'unreachable';
  }
  return { connectionState, httpStatus: statusCode, corridors };
}

function ids(traceparent: string): { traceId: string; spanId: string } {
  const parts = traceparent.split('-');
  return { traceId: parts[1] ?? '', spanId: parts[2] ?? '' };
}

export class TelemetryLog {
  private spanList: SpanRecord[] = [];
  private eventList: TelemetryEvent[] = [];
  private connection = 'unknown';
  private corridorStates = new Map<string, string>();

  spans(): SpanRecord[] {
    return [...this.spanList];
  }

  events(): TelemetryEvent[] {
    return [...this.eventList];
  }

  connectionState(): string {
    return this.connection;
  }

  reset(): void {
    this.spanList = [];
    this.eventList = [];
    this.connection = 'unknown';
    this.corridorStates.clear();
  }

  rendered(): string {
    const spans = this.spanList
      .map((span) => `span ${span.name} ${span.status} ${formatAttributes(span.attributes)}`)
      .join('\n');
    const events = this.eventList
      .map((event) => `event ${event.name} ${event.errorCode} ${event.failureStage} ${formatAttributes(event.attributes)}`)
      .join('\n');
    return `${spans}\n${events}`;
  }

  recordSpan(
    name: string,
    traceparent: string,
    durationMillis: number,
    status: string,
    attributes: Record<string, string | undefined>,
    parentSpanId?: string,
  ): void {
    const parsed = ids(traceparent);
    this.spanList.push({
      name,
      traceId: parsed.traceId,
      spanId: parsed.spanId,
      parentSpanId,
      durationMillis: Math.max(0, Math.round(durationMillis)),
      status,
      attributes: sanitizeAttributes(attributes),
    });
  }

  recordError(code: string, stage: string, attributes: Record<string, string | undefined> = {}): void {
    this.recordEvent('client.error', code, stage, attributes);
  }

  recordEvent(name: string, code: string, stage: string, attributes: Record<string, string | undefined> = {}): void {
    this.eventList.push({
      name,
      errorCode: safeCode(code),
      failureStage: /^[a-z0-9_]{1,64}$/.test(stage) ? stage : 'unknown',
      attributes: sanitizeAttributes(attributes),
    });
  }

  recordCatalogParse(
    parent: string,
    durationMillis: number,
    recipientCount: number,
    providerCount: number,
  ): string {
    const child = `00-${ids(parent).traceId}-${hex(8)}-01`;
    this.recordSpan(
      'catalog.parse',
      child,
      durationMillis,
      'ok',
      {
        'http.route': '/api/v1/catalog',
        'recipient.count': String(recipientCount),
        'provider.count': String(providerCount),
      },
      ids(parent).spanId,
    );
    return child;
  }

  recordGateway(input: {
    traceparent: string;
    durationMillis: number;
    httpStatus: number;
    ok: boolean;
    code?: string;
    message?: string;
    method?: string;
  }): void {
    const provider = input.method === 'card' ? 'adyen' : input.method === 'bank' ? 'worldpay' : undefined;
    const outcome = input.ok ? 'ok' : input.code || 'error';
    const attributes = {
      'http.route': '/api/v1/payments',
      'http.method': 'POST',
      'http.status_code': String(input.httpStatus),
      'payment.method': input.method,
      'payment.provider': provider,
      outcome,
      'error.message': input.ok ? undefined : input.message,
    };
    this.recordSpan('payment.gateway', input.traceparent, input.durationMillis, input.ok ? 'ok' : 'error', attributes);
    if (!input.ok) {
      const code = input.code || 'GATEWAY_ERROR';
      if (code.toUpperCase().includes('SCA')) this.recordEvent('sca.fallback', code, 'sca_challenge', attributes);
      else this.recordError(code, 'gateway_roundtrip', attributes);
    }
  }

  resolveLocalBiometric(method: 'card' | 'bank', accepted = true, available = true): { accepted: boolean; fallback: boolean } {
    const started = performance.now();
    const traceparent = createTraceparent();
    const provider = method === 'card' ? 'adyen' : 'worldpay';
    const attributes = { 'payment.method': method, 'payment.provider': provider };
    const duration = performance.now() - started;
    if (!available) {
      this.recordSpan('biometric.prompt', traceparent, duration, 'fallback', { ...attributes, outcome: 'fallback' });
      this.recordEvent('sca.fallback', 'SCA_CHALLENGE_FALLBACK', 'biometric_prompt', attributes);
      return { accepted: false, fallback: true };
    }
    if (!accepted) {
      this.recordSpan('biometric.prompt', traceparent, duration, 'error', { ...attributes, outcome: 'declined' });
      this.recordError('BIOMETRIC_DECLINED', 'biometric_prompt', attributes);
      return { accepted: false, fallback: false };
    }
    this.recordSpan('biometric.prompt', traceparent, duration, 'ok', { ...attributes, outcome: 'accepted' });
    return { accepted: true, fallback: false };
  }

  observe(report: SessionHealthReport, durationMillis: number): void {
    const previous = this.connection;
    let emittedCorridor = false;
    if (previous !== report.connectionState) {
      this.connection = report.connectionState;
      this.recordEvent('session.connection_changed', report.httpStatus ? `HTTP_${report.httpStatus}` : 'NONE', 'session_health', {
        'connection.previous': previous,
        'connection.current': report.connectionState,
        'http.status_code': report.httpStatus == null ? '' : String(report.httpStatus),
        duration_ms: String(Math.max(0, Math.round(durationMillis))),
      });
    }
    for (const corridor of report.corridors) {
      const prior = this.corridorStates.get(corridor.id) ?? 'unknown';
      if (prior === corridor.state) continue;
      this.corridorStates.set(corridor.id, corridor.state);
      if (corridor.state === 'degraded' || corridor.state === 'down') {
        emittedCorridor = true;
        this.recordEvent('corridor.degraded', `CORRIDOR_${corridor.state.toUpperCase()}`, 'session_health', {
          'corridor.id': corridor.id,
          'corridor.state': corridor.state,
          'connection.previous': prior,
          'connection.current': corridor.state,
          'payment.provider': corridor.provider,
          'payment.method': corridor.method,
        });
      }
    }
    const worsened = report.connectionState === 'degraded' || report.connectionState === 'unreachable';
    if (worsened && previous !== report.connectionState && !emittedCorridor && report.corridors.length === 0) {
      this.recordEvent('corridor.degraded', `CORRIDOR_${report.connectionState.toUpperCase()}`, 'session_health', {
        'corridor.id': 'session',
        'corridor.state': report.connectionState === 'unreachable' ? 'down' : 'degraded',
        'connection.previous': previous,
        'connection.current': report.connectionState,
      });
    }
  }
}

function formatAttributes(attributes: Record<string, string>): string {
  return Object.keys(attributes)
    .sort()
    .map((key) => `${key}=${attributes[key]}`)
    .join(',');
}

export const rehearsalTelemetry = new TelemetryLog();

export async function probeSessionHealth(room: string, telemetry: TelemetryLog = rehearsalTelemetry): Promise<string> {
  const traceparent = createTraceparent();
  const started = performance.now();
  try {
    const response = await fetch('/api/v1/session/health', {
      headers: {
        'Content-Type': 'application/json',
        'X-Rehearsal-Session': room,
        traceparent,
      },
      signal: AbortSignal.timeout(15000),
    });
    const raw = await response.text();
    let body: unknown = null;
    try {
      body = raw ? JSON.parse(raw) : null;
    } catch {
      body = null;
    }
    const report = parseSessionHealth(response.status, body);
    telemetry.recordSpan('session.health', traceparent, performance.now() - started, report.connectionState === 'healthy' ? 'ok' : 'error', {
      'http.route': '/api/v1/session/health',
      'http.method': 'GET',
      'http.status_code': String(response.status),
      'connection.current': report.connectionState,
    });
    telemetry.observe(report, performance.now() - started);
    return report.connectionState;
  } catch {
    const report = parseSessionHealth(0, null);
    telemetry.recordError('NETWORK_ERROR', 'session_health');
    telemetry.observe(report, performance.now() - started);
    return report.connectionState;
  }
}
