/** Local PSD2 SCA step-up for the browser companion rehearsal. Not Face ID or BiometricPrompt. */
export const SCA_CODE = 'SCA_STEP_UP_REQUIRED';
export const EUROPEAN_SCA_PROMPT =
  'Confirm with Face ID / Fingerprint to authorize European payment';
export const SCA_EXPIRED_MESSAGE = 'This step-up window expired. Start the payment again.';
export const SCA_CANCELLED_MESSAGE = 'Biometric confirmation cancelled. Retry the same payment.';
export const SCA_REJECTED_MESSAGE =
  'The authentication challenge was not accepted. Start the payment again.';
export const SCA_MALFORMED_MESSAGE =
  'The bank response did not include a usable challenge token. Retry the same payment.';
export const SCA_LATENCY_MESSAGE =
  'Local authentication verification exceeded 300 ms. Retry the same payment.';
export const SCA_HEADER = 'X-Challenge-Verification';
export const SCA_LATENCY_BUDGET_MS = 300;

export type ScaBody = {
  code?: string;
  challengeToken?: unknown;
  challengeExpiresAt?: unknown;
};

export type ScaChallenge = {
  token: string;
  expiresAtMs: number;
  prompt: string;
};

export type ScaAssessment =
  | { kind: 'not-required' }
  | { kind: 'ready'; challenge: ScaChallenge }
  | { kind: 'expired'; challenge: ScaChallenge }
  | { kind: 'malformed'; message: string };

export function assessSca(status: number, body: ScaBody, now = Date.now()): ScaAssessment {
  if (status !== 202 || body.code !== SCA_CODE) return { kind: 'not-required' };
  if (typeof body.challengeToken !== 'string' || body.challengeToken.length === 0) {
    return { kind: 'malformed', message: SCA_MALFORMED_MESSAGE };
  }
  if (typeof body.challengeExpiresAt !== 'string') {
    return { kind: 'malformed', message: SCA_MALFORMED_MESSAGE };
  }
  const expiresAtMs = Date.parse(body.challengeExpiresAt);
  if (Number.isNaN(expiresAtMs)) return { kind: 'malformed', message: SCA_MALFORMED_MESSAGE };
  const challenge: ScaChallenge = {
    token: body.challengeToken,
    expiresAtMs,
    prompt: EUROPEAN_SCA_PROMPT,
  };
  if (now >= expiresAtMs) return { kind: 'expired', challenge };
  return { kind: 'ready', challenge };
}

/** FNV-1a 64 local proof. This is not a provider cryptogram or a stored credential. */
export function verificationToken(challengeToken: string): string {
  if (!challengeToken) throw new Error(SCA_MALFORMED_MESSAGE);
  const start = performance.now();
  let hash = 14695981039346656037n;
  const prime = 1099511628211n;
  const mask = (1n << 64n) - 1n;
  for (const byte of new TextEncoder().encode(challengeToken)) {
    hash ^= BigInt(byte);
    hash = (hash * prime) & mask;
  }
  const elapsed = performance.now() - start;
  if (elapsed >= SCA_LATENCY_BUDGET_MS) throw new Error(SCA_LATENCY_MESSAGE);
  return `sca_v1_${hash.toString(16).padStart(16, '0')}`;
}
