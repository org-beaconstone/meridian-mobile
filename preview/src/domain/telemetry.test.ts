import { describe, expect, it } from 'vitest';
import {
  canonicalCorridor,
  emptyHealthMemory,
  healthSummary,
  interpretSessionHealth,
  isTraceparent,
  openSpan,
  probeSessionHealth,
  recordedEvents,
  recordedSpans,
  reduceHealth,
  resetTelemetry,
  resolveBiometric,
  sanitize,
} from './telemetry';

describe('browser companion telemetry', () => {
  it('redacts PAN and IBAN and leaves ordinary payment text', () => {
    const cleaned = sanitize(
      'declined 4111111111111111 / 4111-1111-1111-1111 for GB82WEST12345698765432 and GB82 WEST 1234 5698 7654 32',
    );
    expect(cleaned).not.toContain('4111111111111111');
    expect(cleaned).not.toContain('4111-1111');
    expect(cleaned).not.toContain('GB82WEST12345698765432');
    expect(cleaned).not.toContain('WEST 1234');
    expect(cleaned).toContain('[REDACTED_PAN]');
    expect(cleaned).toContain('[REDACTED_IBAN]');
    expect(sanitize('Insufficient balance')).toBe('Insufficient balance');
    expect(sanitize('4111111111111112')).toBe('4111111111111112');
  });

  it('builds a W3C traceparent and times the biometric prompt', () => {
    resetTelemetry();
    const span = openSpan('payment.gateway');
    expect(isTraceparent(span.traceparent)).toBe(true);
    span.end('ok');
    const fallback = resolveBiometric(false);
    expect(fallback.code).toBe('SCA_FALLBACK');
    expect(recordedSpans().some((item) => item.name === 'biometric.prompt' && item.durationMillis >= 0)).toBe(
      true,
    );
    const event = recordedEvents().find((item) => item.code === 'SCA_FALLBACK');
    expect(event?.stage).toBe('biometric');
    expect(JSON.stringify(recordedEvents())).not.toContain('4111');
  });

  it('records corridor degradation without copying sensitive or unknown ids', () => {
    resetTelemetry();
    const body = JSON.stringify({
      status: 'UP',
      connection: 'connected',
      detail: 'GB82WEST12345698765432 4111111111111111',
      corridors: [
        { id: 'adyen-card', state: 'degraded' },
        { id: 'unlisted', provider: 'unlisted', state: 'down', note: '4111111111111111' },
      ],
    });
    const interpreted = interpretSessionHealth(200, body);
    expect(interpreted.reading.connection).toBe('degraded');
    expect(interpreted.reading.corridors.map((corridor) => corridor.id).sort()).toEqual([
      'adyen-card',
      'corridor',
    ]);
    expect(canonicalCorridor('bank')).toBe('worldpay-bank');
    const reduced = reduceHealth(emptyHealthMemory(), interpreted.reading);
    expect(reduced.events.some((event) => event.name === 'corridor.degraded' && event.stage === 'health')).toBe(
      true,
    );
    expect(healthSummary(interpreted.reading)).toContain('adyen-card degraded');
    const again = reduceHealth(reduced.memory, interpreted.reading);
    expect(again.events.filter((event) => event.name === 'corridor.degraded')).toHaveLength(0);
    const blob = JSON.stringify(recordedEvents());
    expect(blob).not.toContain('4111111111111111');
    expect(blob).not.toContain('GB82WEST12345698765432');
    expect(blob).not.toContain('unlisted');
  });

  it('injects traceparent on session health and records a disconnect once', async () => {
    resetTelemetry();
    const seen: Array<Record<string, string>> = [];
    const fetchImpl: typeof fetch = async (_input, init) => {
      const headers = new Headers(init?.headers);
      seen.push({ traceparent: headers.get('traceparent') ?? '', session: headers.get('X-Rehearsal-Session') ?? '' });
      return new Response('missing', { status: 404 });
    };
    const first = await probeSessionHealth('meridian-rehearsal', fetchImpl);
    const second = await probeSessionHealth('meridian-rehearsal', fetchImpl);
    expect(seen).toHaveLength(2);
    expect(seen.every((item) => isTraceparent(item.traceparent) && item.session === 'meridian-rehearsal')).toBe(
      true,
    );
    expect(first.reading.connection).toBe('disconnected');
    expect(first.errorCode).toBe('HTTP_404');
    const memory = emptyHealthMemory();
    const reduced = reduceHealth(memory, first.reading, { code: first.errorCode!, message: first.errorMessage! });
    const repeat = reduceHealth(reduced.memory, second.reading, {
      code: second.errorCode!,
      message: second.errorMessage!,
    });
    expect(reduced.events.some((event) => event.name === 'connection.state')).toBe(true);
    expect(repeat.events.filter((event) => event.name === 'client.error')).toHaveLength(0);
    expect(recordedSpans().filter((span) => span.name === 'session.health')).toHaveLength(2);
  });
});
