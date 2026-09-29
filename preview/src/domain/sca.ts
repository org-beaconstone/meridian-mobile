export const SCA_STEP_UP_CODE = 'SCA_STEP_UP_REQUIRED';
export const BIOMETRIC_PROMPT =
  'Confirm with Face ID / Fingerprint to authorize European payment';
export const FAILURE_MESSAGE =
  'Authentication challenge failed. Please verify with your passcode.';
/** Fictional in-app rehearsal passcode. Checked locally and never sent to the API. */
export const REHEARSAL_PASSCODE = '135790';

export type BiometricStatus = 'success' | 'failed' | 'unavailable' | 'cancelled';
export type ScaPhase = 'biometric' | 'passcode' | 'ready' | 'failed';
export type PaymentMethod = 'card' | 'bank';

export type PaymentDraft = {
  recipientId: string;
  amountMinor: number;
  method: PaymentMethod;
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

export type ScaResubmit = {
  recipientId: string;
  amountMinor: number;
  method: PaymentMethod;
  note: string;
  scenario: string;
  idempotencyKey: string;
  scaChallengeToken: string;
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
  if (typeof value === 'number' && Number.isFinite(value) && value > 0) {
    return value > 10_000_000_000 ? value : value * 1000;
  }
  return null;
}

function text(source: Json | null, key: string): string | null {
  if (!source) return null;
  const value = source[key];
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function object(value: unknown): Json | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value) ? (value as Json) : null;
}

function firstText(source: Json | null, keys: string[]): string | null {
  if (!source) return null;
  for (const key of keys) {
    const found = text(source, key);
    if (found) return found;
  }
  return null;
}

function firstExpiry(source: Json | null, keys: string[]): number | null {
  if (!source) return null;
  for (const key of keys) {
    if (!(key in source)) continue;
    const parsed = parseExpiry(source[key]);
    if (parsed !== null) return parsed;
  }
  return null;
}

export function interpretSca(status: number, body: unknown, now = Date.now()): ScaIntercept {
  const root = object(body);
  if (status !== 202 || !root || root.code !== SCA_STEP_UP_CODE) return { kind: 'notStepUp' };
  const nested = object(root.challenge) ?? object(root.scaChallenge);
  const payload =
    firstText(nested, ['payload', 'challengePayload']) ??
    firstText(root, ['challengePayload', 'payload']) ??
    (typeof root.challenge === 'string' ? root.challenge.trim() || null : null);
  const expiresAt =
    firstExpiry(nested, ['expiresAt', 'expirationTimestamp', 'expiration', 'expiry']) ??
    firstExpiry(root, ['expiresAt', 'expirationTimestamp', 'expiration', 'expiry']);
  if (!payload || expiresAt === null) return { kind: 'invalid' };
  const token =
    firstText(nested, ['scaChallengeToken', 'token']) ?? firstText(root, ['scaChallengeToken', 'token']);
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

export function afterBiometric(
  session: ScaSession,
  status: BiometricStatus,
  now = Date.now(),
): ScaSession {
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
  if (passcodeMatches(entered, expected)) {
    return { ...session, phase: 'ready', token: resubmitToken(session.challenge), message: null };
  }
  return { ...session, phase: 'failed', token: null, message: FAILURE_MESSAGE };
}

export function showsPasscode(session: ScaSession): boolean {
  return session.phase === 'passcode' || session.phase === 'failed';
}

export function resubmit(session: ScaSession): ScaResubmit | null {
  if (session.phase !== 'ready' || !session.token) return null;
  return {
    recipientId: session.draft.recipientId,
    amountMinor: session.draft.amountMinor,
    method: session.draft.method,
    note: session.draft.note,
    scenario: session.draft.scenario,
    idempotencyKey: session.draft.idempotencyKey,
    scaChallengeToken: session.token,
  };
}

export function passcodeMatches(entered: string, expected: string): boolean {
  if (entered.length !== expected.length || expected.length === 0) return false;
  let diff = 0;
  for (let index = 0; index < expected.length; index += 1) {
    diff |= entered.charCodeAt(index) ^ expected.charCodeAt(index);
  }
  return diff === 0;
}
