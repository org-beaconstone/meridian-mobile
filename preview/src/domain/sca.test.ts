import { describe, expect, it } from 'vitest';
import {
  SCA_INCORRECT_PASSCODE,
  SCA_LOCKOUT_SECONDS,
  SCA_REHEARSAL_PIN,
  SCA_REJECTION_BANNER,
  SCA_TOO_MANY_ATTEMPTS,
  appendDigit,
  authenticatedPayload,
  bypassBiometrics,
  createScaEngine,
  deleteDigit,
  hmacHex,
  markBiometricsUnavailable,
  maskedPasscode,
  rehearsalPaymentBody,
  rejectBiometrics,
  secondsLocked,
  sha256Hex,
  succeedBiometrics,
  verifyScaToken,
} from './sca';

const binding = {
  recipientId: 'northline-studio',
  amountMinor: 2599,
  method: 'card' as const,
  idempotencyKey: 'pay-key-1',
};
const now = 1_700_000_000;

function engine() {
  return createScaEngine(binding, { challengeId: 'challenge-1', nonce: 'nonce-1' });
}

function enter(current: ReturnType<typeof engine>, pin: string, at = now) {
  return [...pin].reduce((state, digit) => appendDigit(state, Number(digit), at), current);
}

describe('sca challenge', () => {
  it('matches SHA-256 and HMAC test vectors', () => {
    expect(sha256Hex('')).toBe('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    expect(sha256Hex('abc')).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(hmacHex('key', 'The quick brown fox jumps over the lazy dog')).toBe(
      'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8',
    );
  });

  it('shows the rejection banner only after biometric rejection', () => {
    const rejected = rejectBiometrics(engine());
    expect(rejected.phase).toBe('passcode');
    expect(rejected.rejectionBanner).toBe(SCA_REJECTION_BANNER);
    expect(bypassBiometrics(engine()).rejectionBanner).toBeNull();
    expect(markBiometricsUnavailable(engine()).rejectionBanner).toBeNull();
    expect(markBiometricsUnavailable(engine()).biometric).toBe('unavailable');
  });

  it('signs biometric success as possession plus inherence', () => {
    const verified = succeedBiometrics(engine(), now);
    const token = verified.verification?.scaChallengeToken ?? '';
    expect(verified.verification?.factors).toEqual(['inherence', 'possession']);
    expect(token).not.toContain(SCA_REHEARSAL_PIN);
    expect(authenticatedPayload(token)).toContain('inherence+possession');
    expect(verifyScaToken(token, binding)).toBe(true);
  });

  it('masks the passcode, rate-limits guesses, and packages scaChallengeToken', () => {
    let masking = rejectBiometrics(engine());
    masking = appendDigit(masking, 1, now);
    masking = appendDigit(masking, 2, now);
    expect(maskedPasscode(masking)).toBe('••○○○○');
    expect(maskedPasscode(masking)).not.toMatch(/\d/u);
    masking = appendDigit(masking, 77, now);
    expect(masking.entered).toHaveLength(2);
    masking = deleteDigit(masking, now);
    expect(maskedPasscode(masking)).toBe('•○○○○○');

    let current = rejectBiometrics(engine());
    for (let attempt = 0; attempt < 4; attempt += 1) {
      current = enter(current, '000000');
      expect(current.verification).toBeNull();
      expect(current.passcodeMessage).toBe(SCA_INCORRECT_PASSCODE);
      expect(secondsLocked(current, now)).toBe(0);
    }
    current = enter(current, '000000');
    expect(current.passcodeMessage).toBe(SCA_TOO_MANY_ATTEMPTS);
    expect(secondsLocked(current, now)).toBe(SCA_LOCKOUT_SECONDS);
    current = enter(current, SCA_REHEARSAL_PIN, now + 29);
    expect(current.verification).toBeNull();
    current = enter(current, SCA_REHEARSAL_PIN, now + SCA_LOCKOUT_SECONDS);
    const token = current.verification?.scaChallengeToken ?? '';
    expect(current.verification?.factors).toEqual(['knowledge', 'possession']);
    expect(current.verification?.biometric).toBe('rejected');
    expect(token).not.toContain(SCA_REHEARSAL_PIN);
    expect(authenticatedPayload(token)).toContain('knowledge+possession');
    expect(authenticatedPayload(token)).not.toContain(SCA_REHEARSAL_PIN);
    expect(verifyScaToken(token, binding)).toBe(true);
    expect(verifyScaToken(token, { ...binding, amountMinor: 2600 })).toBe(false);
    const separator = token.indexOf('.');
    const tampered = `${token.slice(0, separator + 1)}${token[separator + 1] === 'A' ? 'B' : 'A'}${token.slice(separator + 2)}`;
    expect(verifyScaToken(tampered, binding)).toBe(false);
  });

  it('keeps the rehearsal payment body on the Java contract', () => {
    const body = JSON.stringify(
      rehearsalPaymentBody({
        recipientId: binding.recipientId,
        amountMinor: binding.amountMinor,
        method: binding.method,
        note: 'Coffee',
        scenario: 'success',
      }),
    );
    expect(body).toContain('"amountMinor":2599');
    expect(body).not.toContain('scaChallengeToken');
    expect(body).not.toContain(SCA_REHEARSAL_PIN);
  });
});
