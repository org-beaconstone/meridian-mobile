import { describe, expect, it } from 'vitest';
import {
  BIOMETRIC_PROMPT,
  FAILURE_MESSAGE,
  REHEARSAL_PASSCODE,
  afterBiometric,
  afterPasscode,
  interpretSca,
  showsPasscode,
  startSession,
} from './sca';

const now = Date.parse('2026-09-29T00:00:00Z');
const future = '2099-01-01T00:00:00Z';
const draft = {
  recipientId: 'northline-studio',
  amountMinor: 4500,
  method: 'card' as const,
  note: 'Studio',
  scenario: 'success',
  idempotencyKey: 'idem-sca-1',
};

describe('PSD2 SCA step-up', () => {
  it('extracts the challenge payload and expiry from HTTP 202', () => {
    const intercept = interpretSca(
      202,
      {
        ok: false,
        code: 'SCA_STEP_UP_REQUIRED',
        challenge: { payload: 'ch_abc', expiresAt: future, token: 'tok_1' },
      },
      now,
    );
    expect(intercept).toEqual({
      kind: 'required',
      challenge: { payload: 'ch_abc', expiresAt: Date.parse(future), token: 'tok_1' },
    });
    expect(BIOMETRIC_PROMPT).toBe('Confirm with Face ID / Fingerprint to authorize European payment');
  });

  it('leaves pending and non-202 responses alone', () => {
    expect(interpretSca(202, { ok: false, code: 'PAYMENT_PENDING' }, now).kind).toBe('notStepUp');
    expect(
      interpretSca(400, { code: 'SCA_STEP_UP_REQUIRED', challengePayload: 'ch', expiresAt: future }, now)
        .kind,
    ).toBe('notStepUp');
  });

  it('rejects a missing payload and an expired challenge', () => {
    expect(
      interpretSca(202, { code: 'SCA_STEP_UP_REQUIRED', challenge: { expiresAt: future } }, now).kind,
    ).toBe('invalid');
    expect(
      interpretSca(
        202,
        { code: 'SCA_STEP_UP_REQUIRED', challengePayload: 'ch_old', expiresAt: '2000-01-01T00:00:00Z' },
        now,
      ).kind,
    ).toBe('expired');
  });

  it('keeps the payment draft when biometrics fall back to passcode', () => {
    const challenge = { payload: 'ch_live', expiresAt: Date.parse(future), token: null };
    const fallback = afterBiometric(startSession(draft, challenge, now), 'unavailable', now);
    expect(showsPasscode(fallback)).toBe(true);
    expect(fallback.draft).toEqual(draft);
    const failed = afterPasscode(fallback, '000000', now);
    expect(failed.message).toBe(FAILURE_MESSAGE);
    expect(failed.draft.amountMinor).toBe(4500);
    expect(failed.draft.recipientId).toBe('northline-studio');
    expect(failed.draft.idempotencyKey).toBe('idem-sca-1');
    const ready = afterPasscode(fallback, REHEARSAL_PASSCODE, now);
    expect(ready.token).toBe('ch_live');
    expect(ready.draft.method).toBe('card');
    expect(ready.draft.idempotencyKey).toBe(draft.idempotencyKey);
  });
});
