import { describe, expect, it } from 'vitest';
import {
  BIOMETRIC_PROMPT,
  FAILURE_MESSAGE,
  REHEARSAL_PASSCODE,
  afterBiometric,
  afterPasscode,
  interpretSca,
  resubmit,
  startSession,
  type PaymentDraft,
} from './sca';

const draft: PaymentDraft = {
  recipientId: 'northline-studio',
  amountMinor: 4500,
  method: 'card',
  note: 'Studio materials',
  scenario: 'success',
  idempotencyKey: 'idem-sca-1',
};

const future = '2099-06-01T12:00:00Z';
const futureMs = Date.parse(future);

function stepUp(extra: Record<string, unknown> = {}) {
  return {
    ok: false,
    code: 'SCA_STEP_UP_REQUIRED',
    challenge: {
      payload: 'payload-eu',
      expiresAt: future,
      scaChallengeToken: 'token-eu',
    },
    ...extra,
  };
}

describe('PSD2 SCA challenge handler', () => {
  it('uses the mandated biometric copy and failure message', () => {
    expect(BIOMETRIC_PROMPT).toBe(
      'Confirm with Face ID / Fingerprint to authorize European payment',
    );
    expect(FAILURE_MESSAGE).toBe(
      'Authentication challenge failed. Please verify with your passcode.',
    );
  });

  it('intercepts HTTP 202 SCA_STEP_UP_REQUIRED and extracts payload plus expiry', () => {
    const intercept = interpretSca(202, stepUp(), futureMs - 1000);
    expect(intercept).toEqual({
      kind: 'required',
      challenge: { payload: 'payload-eu', expiresAt: futureMs, token: 'token-eu' },
    });
  });

  it('leaves HTTP 202 payment pending on the normal path', () => {
    expect(
      interpretSca(202, {
        ok: false,
        code: 'PAYMENT_PENDING',
        error: 'Payment pending confirmation',
        paymentId: 'pay-1',
      }),
    ).toEqual({ kind: 'notStepUp' });
  });

  it('ignores the step-up code unless the status is 202', () => {
    expect(interpretSca(200, stepUp())).toEqual({ kind: 'notStepUp' });
    expect(interpretSca(400, stepUp())).toEqual({ kind: 'notStepUp' });
  });

  it('fails closed when the challenge payload or expiry is missing or already expired', () => {
    expect(
      interpretSca(202, { ok: false, code: 'SCA_STEP_UP_REQUIRED', challenge: { payload: 'only' } }),
    ).toEqual({ kind: 'invalid' });
    const expired = interpretSca(
      202,
      {
        ok: false,
        code: 'SCA_STEP_UP_REQUIRED',
        challengePayload: 'payload-eu',
        expirationTimestamp: '2000-01-01T00:00:00Z',
        scaChallengeToken: 'token-eu',
      },
      Date.parse('2026-09-29T00:00:00Z'),
    );
    expect(expired.kind).toBe('expired');
  });

  it('falls back to the passcode without changing the payment draft', () => {
    const challenge = {
      payload: 'payload-eu',
      expiresAt: futureMs,
      token: 'token-eu',
    };
    const session = startSession(draft, challenge, futureMs - 1000);
    for (const status of ['failed', 'unavailable', 'cancelled'] as const) {
      const next = afterBiometric(session, status, futureMs - 1000);
      expect(next.phase).toBe('passcode');
      expect(next.draft).toEqual(draft);
      expect(next.token).toBeNull();
      expect(resubmit(next)).toBeNull();
    }
  });

  it('resubmits the original key and method with the challenge token after verification', () => {
    const session = startSession(
      draft,
      { payload: 'payload-eu', expiresAt: futureMs, token: 'token-eu' },
      futureMs - 1000,
    );
    const ready = afterBiometric(session, 'success', futureMs - 1000);
    const body = resubmit(ready);
    expect(body).toEqual({
      recipientId: 'northline-studio',
      amountMinor: 4500,
      method: 'card',
      note: 'Studio materials',
      scenario: 'success',
      idempotencyKey: 'idem-sca-1',
      scaChallengeToken: 'token-eu',
    });
    expect(JSON.stringify(body)).not.toContain(REHEARSAL_PASSCODE);
  });

  it('accepts the rehearsal passcode on device and rejects anything else', () => {
    const started = startSession(
      draft,
      { payload: 'payload-eu', expiresAt: futureMs, token: null },
      futureMs - 1000,
    );
    const passcode = afterBiometric(started, 'unavailable', futureMs - 1000);
    const wrong = afterPasscode(passcode, '111111', futureMs - 1000);
    expect(wrong.phase).toBe('failed');
    expect(wrong.message).toBe(FAILURE_MESSAGE);
    expect(wrong.draft).toEqual(draft);
    expect(resubmit(wrong)).toBeNull();
    const verified = afterPasscode(wrong, REHEARSAL_PASSCODE, futureMs - 1000);
    expect(resubmit(verified)?.scaChallengeToken).toBe('payload-eu');
    expect(resubmit(verified)?.idempotencyKey).toBe(draft.idempotencyKey);
    expect(resubmit(verified)?.method).toBe('card');
  });

  it('shows the failure message when the challenge expires during passcode entry', () => {
    const passcode = afterBiometric(
      startSession(draft, { payload: 'payload-eu', expiresAt: futureMs, token: 'token-eu' }, 0),
      'failed',
      0,
    );
    const expired = afterPasscode(passcode, REHEARSAL_PASSCODE, futureMs);
    expect(expired.message).toBe(FAILURE_MESSAGE);
    expect(expired.draft.recipientId).toBe('northline-studio');
    expect(expired.draft.amountMinor).toBe(4500);
    expect(resubmit(expired)).toBeNull();
  });
});
