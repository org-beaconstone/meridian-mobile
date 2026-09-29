export const SCA_STEP_UP_CODE = 'SCA_STEP_UP_REQUIRED';
export const BIOMETRIC_PROMPT = 'Confirm with Face ID / Fingerprint to authorize European payment';
export const FAILURE_MESSAGE = 'Authentication challenge failed. Please verify with your passcode.';
/** Fictional in-app rehearsal passcode. Checked locally and never sent to the API. */
export const REHEARSAL_PASSCODE = '135790';

export type BiometricStatus = 'success' | 'failed' | 'unavailable' | 'cancelled';
export type ScaPhase = 'biometric' | 'passcode' | 'ready' | 'failed';
export type PaymentMethodName = 'card' | 'bank';

export type PaymentDraft = {
  recipientId: string;
  amountMinor: number;
  method: PaymentMethodName;
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

export function passcodeMatches(entered: string, expected = REHEARSAL_PASSCODE): boolean {
  if (entered.length !== 6 || expected.length !== 6 || !/^\d{6}$/.test(entered)) return false;
  let diff = 0;
  for (let index = 0; index < 6; index += 1) {
    diff |= entered.charCodeAt(index) ^ expected.charCodeAt(index);
  }
  return diff === 0;
}

function text(source: Json | null, key: string): string | null {
  if (!source) return null;
  const value = source[key];
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : null;
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
        parseExpiry(nested.expirationTimestamp) ??
        parseExpiry(nested.expiry))) ??
    parseExpiry(root.expiresAt) ??
    parseExpiry(root.expiration) ??
    parseExpiry(root.expirationTimestamp);
  if (!payload || expiresAt === null) return { kind: 'invalid' };
  const token =
    (nested && (text(nested, 'scaChallengeToken') ?? text(nested, 'token'))) ??
    text(root, 'scaChallengeToken') ??
    text(root, 'token');
  const challenge = { payload, expiresAt, token };
  if (now >= expiresAt) return { kind: 'expired', challenge };
  return { kind: 'required', challenge };
}

export function startSession(
  draft: PaymentDraft,
  challenge: ScaChallenge,
  now = Date.now(),
): ScaSession {
  if (now >= challenge.expiresAt) {
    return { draft, challenge, phase: 'failed', message: FAILURE_MESSAGE };
  }
  return { draft, challenge, phase: 'biometric', message: null };
}

export function afterBiometric(
  session: ScaSession,
  status: BiometricStatus,
  now = Date.now(),
): ScaSession {
  if (session.phase !== 'biometric') return session;
  if (now >= session.challenge.expiresAt) {
    return { ...session, phase: 'failed', message: FAILURE_MESSAGE };
  }
  if (status === 'success') return { ...session, phase: 'ready', message: null };
  return { ...session, phase: 'passcode', message: null };
}

export function afterPasscode(
  session: ScaSession,
  entered: string,
  now = Date.now(),
  expected = REHEARSAL_PASSCODE,
): ScaSession {
  if (session.phase !== 'passcode' && session.phase !== 'failed') return session;
  if (now >= session.challenge.expiresAt) {
    return { ...session, phase: 'failed', message: FAILURE_MESSAGE };
  }
  if (passcodeMatches(entered, expected)) return { ...session, phase: 'ready', message: null };
  return { ...session, phase: 'failed', message: FAILURE_MESSAGE };
}

export function sessionToken(session: ScaSession): string | null {
  return session.phase === 'ready' ? resubmitToken(session.challenge) : null;
}

export function showsPasscode(session: ScaSession): boolean {
  return session.phase === 'passcode' || session.phase === 'failed';
}

/** Payment JSON for the original key. The passcode is never a field. */
export function paymentBody(draft: PaymentDraft, scaChallengeToken?: string | null): Json {
  const body: Json = {
    recipientId: draft.recipientId,
    amountMinor: draft.amountMinor,
    method: draft.method,
    note: draft.note,
    scenario: draft.scenario,
  };
  if (scaChallengeToken) body.scaChallengeToken = scaChallengeToken;
  return body;
}
