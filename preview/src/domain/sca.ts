export const SCA_STEP_UP_REQUIRED = 'SCA_STEP_UP_REQUIRED';
export const BIOMETRIC_PROMPT =
  'Confirm with Face ID / Fingerprint to authorize European payment';
export const SCA_FAILURE_MESSAGE =
  'Authentication challenge failed. Please verify with your passcode.';

export type PaymentMethod = 'card' | 'bank';

export type InFlightPayment = {
  recipientId: string;
  amountMinor: number;
  method: PaymentMethod;
  note: string;
  scenario: string;
  idempotencyKey: string;
};

export type ScaChallenge = {
  payload: string;
  expiresAtMs: number;
  scaChallengeToken: string;
};

export type ScaPhase =
  | { kind: 'biometric'; challenge: ScaChallenge }
  | { kind: 'passcode'; challenge: ScaChallenge; message: string | null }
  | { kind: 'ready'; challenge: ScaChallenge }
  | { kind: 'failed'; message: string };

export type ScaHandler = {
  payment: InFlightPayment;
  phase: ScaPhase;
};

export type ScaResubmission = {
  idempotencyKey: string;
  body: {
    recipientId: string;
    amountMinor: number;
    method: PaymentMethod;
    note: string;
    scenario: string;
    scaChallengeToken: string;
  };
};

function text(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  const trimmed = value.trim();
  return trimmed === '' ? undefined : trimmed;
}

function field(record: Record<string, unknown>, key: string): string | undefined {
  return text(record[key]);
}

export function extractScaChallenge(
  statusCode: number,
  body: unknown,
): ScaChallenge | 'not-sca' | 'invalid' {
  if (statusCode !== 202 || !body || typeof body !== 'object') return 'not-sca';
  const record = body as Record<string, unknown>;
  if (record.code !== SCA_STEP_UP_REQUIRED) return 'not-sca';

  const challenge = record.challenge;
  let payload: string | undefined;
  let expiresRaw: string | undefined;
  let token: string | undefined;
  if (typeof challenge === 'string') {
    payload = text(challenge);
  } else if (challenge && typeof challenge === 'object') {
    const nested = challenge as Record<string, unknown>;
    payload = field(nested, 'payload');
    expiresRaw =
      field(nested, 'expiresAt') ??
      field(nested, 'expirationTimestamp') ??
      field(nested, 'expiration');
    token = field(nested, 'scaChallengeToken') ?? field(nested, 'token');
  }
  payload = payload ?? field(record, 'challengePayload');
  expiresRaw =
    expiresRaw ??
    field(record, 'expiresAt') ??
    field(record, 'expirationTimestamp') ??
    field(record, 'expiration');
  token = token ?? field(record, 'scaChallengeToken');
  if (!payload || !expiresRaw || !token) return 'invalid';
  const expiresAtMs = Date.parse(expiresRaw);
  if (Number.isNaN(expiresAtMs)) return 'invalid';
  return { payload, expiresAtMs, scaChallengeToken: token };
}

/** Null when the response is not an HTTP 202 step-up. Expired challenges fail closed. */
export function beginSca(
  statusCode: number,
  body: unknown,
  payment: InFlightPayment,
  nowMs: number,
): ScaHandler | null {
  const extracted = extractScaChallenge(statusCode, body);
  if (extracted === 'not-sca') return null;
  if (extracted === 'invalid' || extracted.expiresAtMs <= nowMs) {
    return { payment, phase: { kind: 'failed', message: SCA_FAILURE_MESSAGE } };
  }
  return { payment, phase: { kind: 'biometric', challenge: extracted } };
}

export function biometricUnavailableOrFailed(handler: ScaHandler, nowMs: number): ScaHandler {
  if (handler.phase.kind !== 'biometric') return handler;
  if (handler.phase.challenge.expiresAtMs <= nowMs) {
    return { payment: handler.payment, phase: { kind: 'failed', message: SCA_FAILURE_MESSAGE } };
  }
  return {
    payment: handler.payment,
    phase: { kind: 'passcode', challenge: handler.phase.challenge, message: null },
  };
}

export function biometricSucceeded(handler: ScaHandler, nowMs: number): ScaHandler {
  if (handler.phase.kind !== 'biometric') return handler;
  if (handler.phase.challenge.expiresAtMs <= nowMs) {
    return { payment: handler.payment, phase: { kind: 'failed', message: SCA_FAILURE_MESSAGE } };
  }
  return { payment: handler.payment, phase: { kind: 'ready', challenge: handler.phase.challenge } };
}

export function passcodeVerified(handler: ScaHandler, nowMs: number): ScaHandler {
  if (handler.phase.kind !== 'passcode') return handler;
  if (handler.phase.challenge.expiresAtMs <= nowMs) {
    return { payment: handler.payment, phase: { kind: 'failed', message: SCA_FAILURE_MESSAGE } };
  }
  return { payment: handler.payment, phase: { kind: 'ready', challenge: handler.phase.challenge } };
}

export function passcodeRejected(handler: ScaHandler, nowMs: number): ScaHandler {
  if (handler.phase.kind !== 'passcode') return handler;
  if (handler.phase.challenge.expiresAtMs <= nowMs) {
    return { payment: handler.payment, phase: { kind: 'failed', message: SCA_FAILURE_MESSAGE } };
  }
  return {
    payment: handler.payment,
    phase: {
      kind: 'passcode',
      challenge: handler.phase.challenge,
      message: SCA_FAILURE_MESSAGE,
    },
  };
}

/** Token is released only after verification, on the original key and method. */
export function resubmitPayment(handler: ScaHandler): ScaResubmission | null {
  if (handler.phase.kind !== 'ready') return null;
  return {
    idempotencyKey: handler.payment.idempotencyKey,
    body: {
      recipientId: handler.payment.recipientId,
      amountMinor: handler.payment.amountMinor,
      method: handler.payment.method,
      note: handler.payment.note,
      scenario: handler.payment.scenario,
      scaChallengeToken: handler.phase.challenge.scaChallengeToken,
    },
  };
}

/** Local comparison only. The passcode is not part of the payment body. */
export function passcodeMatches(entered: string, enrolled: string): boolean {
  if (!/^\d{6}$/.test(entered) || !/^\d{6}$/.test(enrolled)) return false;
  let diff = 0;
  for (let index = 0; index < entered.length; index += 1) {
    diff |= entered.charCodeAt(index) ^ enrolled.charCodeAt(index);
  }
  return diff === 0;
}
