export const SCA_STEP_UP_CODE = 'SCA_STEP_UP_REQUIRED';
export const BIOMETRIC_PROMPT = 'Confirm with Face ID / Fingerprint to authorize European payment';
export const FAILURE_MESSAGE = 'Authentication challenge failed. Please verify with your passcode.';
/** Fictional in-app rehearsal passcode. Checked locally and never sent to the API. */
export const REHEARSAL_PASSCODE = '135790';

export type BiometricStatus = 'success' | 'failed' | 'unavailable' | 'cancelled';
export type ScaPhase = 'biometric' | 'passcode' | 'ready' | 'failed';

export type PaymentDraft = {
  recipientId: string;
  amountMinor: number;
  method: 'card' | 'bank';
  note: string;
  scenario: string;
  idempotencyKey: string;
};

export type ScaChallenge = {
  payload: string;
  expiresAt: number;
  token: string | null;
};

export type ScaIntercept =
  | { kind: 'notStepUp' }
  | { kind: 'invalid' }
  | { kind: 'expired'; challenge: ScaChallenge }
  | { kind: 'required'; challenge: ScaChallenge };

export type ScaSession = {
  draft: PaymentDraft;
  challenge: ScaChallenge;
  phase: ScaPhase;
  token: string | null;
  message: string | null;
};

type Json = Record<string, unknown>;

export function resubmitToken(challenge: ScaChallenge): string {
  return challenge.token && challenge.token.length > 0 ? challenge.token : challenge.payload;
}

export function parseExpiry(value: unknown): number | null {
  if (typeof value === 'string') {
    const ms = Date.parse(value);
    return Number.isNaN(ms) ? null : ms;
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value > 10_000_000_000 ? value : value * 1000;
  }
  return null;
}

function text(source: Json, key: string): string | null {
  const value = source[key];
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function object(value: unknown): Json | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? (value as Json)
    : null;
}

export function interpretSca(status: number, body: unknown, now = Date.now()): ScaIntercept {
  const root = object(body);
  if (status !== 202 || !root || root.code !== SCA_STEP_UP_CODE) return { kind: 'notStepUp' };
  const nested = object(root.challenge) ?? object(root.scaChallenge);
  const payload =
    (nested && (text(nested, 'payload') ?? text(nested, 'challengePayload'))) ??
    text(root, 'challengePayload') ??
    text(root, 'payload');
  const expiresAt =
    (nested &&
      (parseExpiry(nested.expiresAt) ??
        parseExpiry(nested.expiration) ??
        parseExpiry(nested.expiry))) ??
    parseExpiry(root.expiresAt) ??
    parseExpiry(root.expiration);
  if (!payload || expiresAt === null) return { kind: 'invalid' };
  const token =
    (nested && (text(nested, 'token') ?? text(nested, 'scaChallengeToken'))) ??
    text(root, 'scaChallengeToken');
  const challenge = { payload, expiresAt, token };
  if (now >= expiresAt) return { kind: 'expired', challenge };
  return { kind: 'required', challenge };
}

export function startSession(draft: PaymentDraft, challenge: ScaChallenge, now = Date.now()): ScaSession {
  if (now >= challenge.expiresAt) {
    return { draft, challenge, phase: 'failed', token: null, message: FAILURE_MESSAGE };
  }
  return { draft, challenge, phase: 'biometric', token: null, message: null };
}

export function afterBiometric(session: ScaSession, status: BiometricStatus, now = Date.now()): ScaSession {
  if (session.phase !== 'biometric') return session;
  if (now >= session.challenge.expiresAt) {
    return { ...session, phase: 'failed', token: null, message: FAILURE_MESSAGE };
  }
  if (status === 'success') {
    return { ...session, phase: 'ready', token: resubmitToken(session.challenge), message: null };
  }
  return { ...session, phase: 'passcode', token: null, message: null };
}

export function afterPasscode(
  session: ScaSession,
  entered: string,
  now = Date.now(),
  expected = REHEARSAL_PASSCODE,
): ScaSession {
  if (session.phase !== 'passcode' && session.phase !== 'failed') return session;
  if (now >= session.challenge.expiresAt) {
    return { ...session, phase: 'failed', token: null, message: FAILURE_MESSAGE };
  }
  if (entered === expected) {
    return { ...session, phase: 'ready', token: resubmitToken(session.challenge), message: null };
  }
  return { ...session, phase: 'failed', token: null, message: FAILURE_MESSAGE };
}

export function showsPasscode(session: ScaSession): boolean {
  return session.phase === 'passcode' || session.phase === 'failed';
}
