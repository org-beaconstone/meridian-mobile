import { describe, expect, it } from 'vitest';
import {
  FAILURE_MESSAGE,
  REHEARSAL_PASSCODE,
  afterBiometric,
  afterPasscode,
  interpretSca,
  passcodeMatches,
  paymentBody,
  sessionToken,
  startSession,
  type PaymentDraft,
} from './sca';

const now = Date.parse('2026-09-29T00:00:00Z');
const draft: PaymentDraft = {
  recipientId: 'northline-studio',
  amountMinor: 4000,
  method: 'card',
  note: 'Studio',
  scenario: 'success',
  idempotencyKey: 'same-key',
};

describe('SCA step-up', () => {
  it('extracts a 202 challenge and ignores pending payments', () => {
    const required = interpretSca(
      202,
      {
        ok: false,
        code: 'SCA_STEP_UP_REQUIRED',
        challenge: { payload: 'ch_abc', expiresAt: '2099-01-01T00:00:00Z', token: 'tok_1' },
      },
      now,
    );
    expect(required).toMatchObject({
      kind: 'required',
      challenge: { payload: 'ch_abc', token: 'tok_1' },
    });
    expect(
      interpretSca(202, { ok: false, code: 'PAYMENT_PENDING', paymentId: 'pay-1' }, now).kind,
    ).toBe('notStepUp');
    expect(
      interpretSca(
        400,
        { code: 'SCA_STEP_UP_REQUIRED', challenge: { payload: 'ch', expiresAt: '2099-01-01T00:00:00Z' } },
        now,
      ).kind,
    ).toBe('notStepUp');
    expect(
      interpretSca(202, { code: 'SCA_STEP_UP_REQUIRED', challenge: { expiresAt: '2099-01-01T00:00:00Z' } }, now)
        .kind,
    ).toBe('invalid');
    expect(
      interpretSca(202, { code: 'SCA_STEP_UP_REQUIRED', challengePayload: 'old', expiresAt: '2000-01-01T00:00:00Z' }, now)
        .kind,
    ).toBe('expired');
  });

  it('keeps the draft when the passcode fails and omits the passcode from the body', () => {
    const challenge = {
      payload: 'ch_live',
      expiresAt: Date.parse('2099-01-01T00:00:00Z'),
      token: 'tok_live',
    };
    let session = startSession(draft, challenge, now);
    session = afterBiometric(session, 'unavailable', now);
    expect(session.phase).toBe('passcode');
    expect(session.draft).toEqual(draft);
    session = afterPasscode(session, '000000', now);
    expect(session.message).toBe(FAILURE_MESSAGE);
    expect(sessionToken(session)).toBeNull();
    expect(session.draft.amountMinor).toBe(4000);
    expect(session.draft.recipientId).toBe('northline-studio');
    session = afterPasscode(session, REHEARSAL_PASSCODE, now);
    expect(sessionToken(session)).toBe('tok_live');
    expect(passcodeMatches('135791')).toBe(false);

    const first = paymentBody(draft);
    const second = paymentBody({ ...draft, method: 'bank' }, 'tok_live');
    expect(first).not.toHaveProperty('scaChallengeToken');
    expect(JSON.stringify(first)).not.toContain(REHEARSAL_PASSCODE);
    expect(second).toMatchObject({ method: 'bank', scaChallengeToken: 'tok_live', amountMinor: 4000 });
    expect(JSON.stringify(second)).not.toContain(REHEARSAL_PASSCODE);
  });
});
