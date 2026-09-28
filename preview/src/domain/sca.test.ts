import { describe, expect, it } from 'vitest';
import {
  BIOMETRIC_PROMPT,
  SCA_FAILURE_MESSAGE,
  beginSca,
  biometricUnavailableOrFailed,
  passcodeMatches,
  passcodeRejected,
  passcodeVerified,
  resubmitPayment,
  type InFlightPayment,
} from './sca';

const payment: InFlightPayment = {
  recipientId: 'northline-studio',
  amountMinor: 4500,
  method: 'card',
  note: 'Studio supplies',
  scenario: 'success',
  idempotencyKey: 'idem-original',
};
const now = Date.parse('2026-09-28T21:00:00Z');

describe('PSD2 SCA challenge handler', () => {
  it('uses the rehearsal prompt and failure copy', () => {
    expect(BIOMETRIC_PROMPT).toBe(
      'Confirm with Face ID / Fingerprint to authorize European payment',
    );
    expect(SCA_FAILURE_MESSAGE).toBe(
      'Authentication challenge failed. Please verify with your passcode.',
    );
  });

  it('extracts the challenge and falls back without releasing the token', () => {
    const handler = beginSca(
      202,
      {
        ok: false,
        code: 'SCA_STEP_UP_REQUIRED',
        challenge: {
          payload: 'challenge-payload',
          expiresAt: '2099-01-01T00:00:00Z',
          scaChallengeToken: 'token-123',
        },
      },
      payment,
      now,
    );
    expect(handler?.phase.kind).toBe('biometric');
    expect(resubmitPayment(handler!)).toBeNull();
    const passcode = biometricUnavailableOrFailed(handler!, now);
    expect(passcode.phase.kind).toBe('passcode');
    expect(passcode.payment).toEqual(payment);
    const rejected = passcodeRejected(passcode, now);
    expect(rejected.phase).toMatchObject({
      kind: 'passcode',
      message: SCA_FAILURE_MESSAGE,
    });
    expect(rejected.payment.recipientId).toBe('northline-studio');
    expect(rejected.payment.amountMinor).toBe(4500);
    expect(rejected.payment.idempotencyKey).toBe('idem-original');
    expect(resubmitPayment(rejected)).toBeNull();
  });

  it('resubmits the original key, method, and token after the passcode', () => {
    const ready = passcodeVerified(
      biometricUnavailableOrFailed(
        beginSca(
          202,
          {
            ok: false,
            code: 'SCA_STEP_UP_REQUIRED',
            challengePayload: 'opaque-payload',
            expirationTimestamp: '2099-06-01T12:00:00Z',
            scaChallengeToken: 'token-from-gateway',
          },
          payment,
          now,
        )!,
        now,
      ),
      now,
    );
    expect(resubmitPayment(ready)).toEqual({
      idempotencyKey: 'idem-original',
      body: {
        recipientId: 'northline-studio',
        amountMinor: 4500,
        method: 'card',
        note: 'Studio supplies',
        scenario: 'success',
        scaChallengeToken: 'token-from-gateway',
      },
    });
    expect(passcodeMatches('135790', '135790')).toBe(true);
    expect(passcodeMatches('000000', '135790')).toBe(false);
  });

  it('keeps the payment when the challenge is expired and ignores other 202 codes', () => {
    const expired = beginSca(
      202,
      {
        ok: false,
        code: 'SCA_STEP_UP_REQUIRED',
        challenge: 'stale-payload',
        expiresAt: '2000-01-01T00:00:00Z',
        scaChallengeToken: 'stale-token',
      },
      payment,
      now,
    );
    expect(expired?.phase).toEqual({ kind: 'failed', message: SCA_FAILURE_MESSAGE });
    expect(expired?.payment).toEqual(payment);
    expect(resubmitPayment(expired!)).toBeNull();
    expect(beginSca(202, { ok: false, code: 'PAYMENT_PENDING' }, payment, now)).toBeNull();
    expect(
      beginSca(
        400,
        {
          ok: false,
          code: 'SCA_STEP_UP_REQUIRED',
          challenge: 'payload',
          expiresAt: '2099-01-01T00:00:00Z',
          scaChallengeToken: 'token',
        },
        payment,
        now,
      ),
    ).toBeNull();
  });
});
