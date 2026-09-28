import { describe, expect, it } from 'vitest';
import {
  TelemetryLog,
  containsSensitive,
  createTraceparent,
  isValidTraceparent,
  parseSessionHealth,
  redact,
  shouldInjectTraceparent,
} from './telemetry';

const pan = '4111111111111111';
const iban = 'GB29NWBK60161331926819';
const noteIban = 'DE89370400440532013000';
const spacedIban = 'GB29 NWBK 6016 1331 9268 19';

describe('browser companion telemetry', () => {
  it('builds a W3C traceparent and selects payment routes', () => {
    expect(isValidTraceparent(createTraceparent())).toBe(true);
    expect(isValidTraceparent(`00-${'0'.repeat(32)}-${'1'.repeat(16)}-01`)).toBe(false);
    expect(shouldInjectTraceparent('/catalog')).toBe(true);
    expect(shouldInjectTraceparent('/payments')).toBe(true);
    expect(shouldInjectTraceparent('/session/health')).toBe(true);
    expect(shouldInjectTraceparent('/health')).toBe(false);
    expect(shouldInjectTraceparent('/state')).toBe(false);
  });

  it('redacts card numbers and IBANs', () => {
    expect(redact(pan)).toBe('[REDACTED_PAN]');
    expect(redact('4111-1111-1111-1111')).toBe('[REDACTED_PAN]');
    expect(redact(iban)).toBe('[REDACTED_IBAN]');
    expect(redact(noteIban)).toBe('[REDACTED_IBAN]');
    expect(redact(spacedIban)).toBe('[REDACTED_IBAN]');
    expect(redact('balance 1248050')).toBe('balance 1248050');
    expect(containsSensitive('PAYMENT_PENDING')).toBe(false);
  });

  it('drops notes, foreign providers, and sensitive codes', () => {
    const log = new TelemetryLog();
    log.recordError(iban, 'gateway_roundtrip', {
      note: noteIban,
      detail: pan,
      'error.message': `declined ${pan} ${spacedIban}`,
      'payment.provider': 'other',
      'payment.method': 'card',
      outcome: 'DECLINED',
    });
    const rendered = log.rendered();
    expect(rendered).not.toContain(pan);
    expect(rendered).not.toContain(iban);
    expect(rendered).not.toContain(noteIban);
    expect(rendered).not.toContain('other');
    expect(rendered).toContain('REDACTED_CODE');
    expect(rendered).toContain('[REDACTED_PAN]');
    expect(rendered).toContain('payment.method=card');
  });

  it('times the local biometric prompt and an SCA fallback', () => {
    const log = new TelemetryLog();
    const accepted = log.resolveLocalBiometric('card');
    expect(accepted).toEqual({ accepted: true, fallback: false });
    expect(log.spans().some((span) => span.name === 'biometric.prompt' && span.status === 'ok')).toBe(true);
    const fallback = log.resolveLocalBiometric('bank', true, false);
    expect(fallback.fallback).toBe(true);
    expect(log.events().some((event) => event.name === 'sca.fallback' && event.failureStage === 'biometric_prompt')).toBe(
      true,
    );
  });

  it('records gateway failures without the payment note', () => {
    const log = new TelemetryLog();
    const traceparent = createTraceparent();
    log.recordGateway({
      traceparent,
      durationMillis: 12,
      httpStatus: 422,
      ok: false,
      code: 'DECLINED',
      message: `card ${pan} iban ${iban}`,
      method: 'card',
    });
    const rendered = log.rendered();
    expect(rendered).not.toContain(pan);
    expect(rendered).not.toContain(noteIban);
    expect(rendered).not.toContain(iban);
    expect(log.spans()[0]?.spanId).toBe(traceparent.split('-')[2]);
    expect(log.events()[0]).toMatchObject({ errorCode: 'DECLINED', failureStage: 'gateway_roundtrip' });
    log.recordGateway({
      traceparent: createTraceparent(),
      durationMillis: 4,
      httpStatus: 422,
      ok: false,
      code: 'SCA_REQUIRED',
      message: 'challenge',
      method: 'bank',
    });
    expect(log.events().some((event) => event.name === 'sca.fallback' && event.attributes['payment.provider'] === 'worldpay')).toBe(
      true,
    );
  });

  it('emits a corridor event when session health degrades', () => {
    const log = new TelemetryLog();
    log.observe(parseSessionHealth(200, { status: 'UP', service: 'meridian-api', simulation: true }), 3);
    const changes = log.events().filter((event) => event.name === 'session.connection_changed').length;
    log.observe(parseSessionHealth(200, { status: 'UP' }), 3);
    expect(log.events().filter((event) => event.name === 'session.connection_changed')).toHaveLength(changes);
    log.observe(
      parseSessionHealth(200, {
        status: 'degraded',
        corridors: [
          { id: 'adyen-card', provider: 'adyen', method: 'card', state: 'degraded' },
          { id: 'other-wallet', provider: 'other', method: 'card', state: 'degraded' },
        ],
      }),
      8,
    );
    expect(log.connectionState()).toBe('degraded');
    expect(log.rendered()).not.toContain('other');
    expect(log.events().some((event) => event.name === 'corridor.degraded' && event.attributes['corridor.id'] === 'adyen-card')).toBe(
      true,
    );
  });
});
