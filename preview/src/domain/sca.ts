const K = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]);

function rotr(value: number, bits: number) {
  return (value >>> bits) | (value << (32 - bits));
}

export function sha256(data: Uint8Array): Uint8Array {
  const bitLength = data.length * 8;
  const padded = new Uint8Array((((data.length + 9 + 63) >> 6) << 6));
  padded.set(data);
  padded[data.length] = 0x80;
  const view = new DataView(padded.buffer);
  view.setUint32(padded.length - 8, Math.floor(bitLength / 0x100000000), false);
  view.setUint32(padded.length - 4, bitLength >>> 0, false);

  let h0 = 0x6a09e667;
  let h1 = 0xbb67ae85;
  let h2 = 0x3c6ef372;
  let h3 = 0xa54ff53a;
  let h4 = 0x510e527f;
  let h5 = 0x9b05688c;
  let h6 = 0x1f83d9ab;
  let h7 = 0x5be0cd19;
  const words = new Uint32Array(64);

  for (let offset = 0; offset < padded.length; offset += 64) {
    for (let index = 0; index < 16; index += 1) words[index] = view.getUint32(offset + index * 4, false);
    for (let index = 16; index < 64; index += 1) {
      const s0 = rotr(words[index - 15], 7) ^ rotr(words[index - 15], 18) ^ (words[index - 15] >>> 3);
      const s1 = rotr(words[index - 2], 17) ^ rotr(words[index - 2], 19) ^ (words[index - 2] >>> 10);
      words[index] = (words[index - 16] + s0 + words[index - 7] + s1) >>> 0;
    }
    let a = h0;
    let b = h1;
    let c = h2;
    let d = h3;
    let e = h4;
    let f = h5;
    let g = h6;
    let h = h7;
    for (let index = 0; index < 64; index += 1) {
      const s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const ch = (e & f) ^ (~e & g);
      const temp1 = (h + s1 + ch + K[index] + words[index]) >>> 0;
      const s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const temp2 = (s0 + maj) >>> 0;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) >>> 0;
    }
    h0 = (h0 + a) >>> 0;
    h1 = (h1 + b) >>> 0;
    h2 = (h2 + c) >>> 0;
    h3 = (h3 + d) >>> 0;
    h4 = (h4 + e) >>> 0;
    h5 = (h5 + f) >>> 0;
    h6 = (h6 + g) >>> 0;
    h7 = (h7 + h) >>> 0;
  }

  const out = new Uint8Array(32);
  const outView = new DataView(out.buffer);
  [h0, h1, h2, h3, h4, h5, h6, h7].forEach((value, index) => outView.setUint32(index * 4, value, false));
  return out;
}

export function hmacSha256(key: Uint8Array, message: Uint8Array): Uint8Array {
  const block = 64;
  const normalized = key.length > block ? sha256(key) : key;
  const padded = new Uint8Array(block);
  padded.set(normalized);
  const outer = new Uint8Array(block);
  const inner = new Uint8Array(block);
  for (let index = 0; index < block; index += 1) {
    outer[index] = padded[index] ^ 0x5c;
    inner[index] = padded[index] ^ 0x36;
  }
  const innerMessage = new Uint8Array(block + message.length);
  innerMessage.set(inner);
  innerMessage.set(message, block);
  const outerMessage = new Uint8Array(block + 32);
  outerMessage.set(outer);
  outerMessage.set(sha256(innerMessage), block);
  return sha256(outerMessage);
}

export const SCA_REJECTION_BANNER =
  'Authentication challenge failed. Please verify with your passcode.';
export const SCA_BIOMETRICS_UNAVAILABLE = 'Biometrics are unavailable on this device.';
export const SCA_INCORRECT_PASSCODE = 'Incorrect passcode.';
export const SCA_TOO_MANY_ATTEMPTS = 'Too many attempts. Try again shortly.';
export const SCA_PIN_LENGTH = 6;
export const SCA_MAX_ATTEMPTS = 5;
export const SCA_LOCKOUT_SECONDS = 30;
export const SCA_REHEARSAL_PIN = '135790';
const SALT = 'meridian-sca-rehearsal-salt-v1';
const DEVICE_KEY_MATERIAL = 'meridian-sca-rehearsal-device-v1';
const IN_APP_BINDING = 'meridian-in-app';

export type ScaFactor = 'possession' | 'knowledge' | 'inherence';
export type BiometricOutcome = 'succeeded' | 'rejected' | 'bypassed' | 'unavailable';
export type ScaMethod = 'card' | 'bank';

export type ScaPaymentBinding = {
  recipientId: string;
  amountMinor: number;
  method: ScaMethod;
  idempotencyKey: string;
};

export type ScaVerification = {
  scaChallengeToken: string;
  factors: ScaFactor[];
  biometric: BiometricOutcome;
};

export type ScaEngine = {
  binding: ScaPaymentBinding;
  phase: 'biometric' | 'passcode' | 'verified';
  rejectionBanner: string | null;
  biometric: BiometricOutcome | null;
  entered: string;
  failures: number;
  lockedUntil: number | null;
  passcodeMessage: string | null;
  verification: ScaVerification | null;
  challengeId: string;
  nonce: string;
};

const textEncoder = new TextEncoder();

function utf8(value: string) {
  return textEncoder.encode(value);
}

function constantTimeEqual(left: Uint8Array, right: Uint8Array) {
  if (left.length !== right.length) return false;
  let diff = 0;
  for (let index = 0; index < left.length; index += 1) diff |= left[index] ^ right[index];
  return diff === 0;
}

function bytesToBase64Url(bytes: Uint8Array) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/u, '');
}

function base64UrlToBytes(value: string) {
  const padded = value.replaceAll('-', '+').replaceAll('_', '/') + '='.repeat((4 - (value.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

function hex(bytes: Uint8Array) {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

const rehearsalKey = sha256(utf8(DEVICE_KEY_MATERIAL));
const expectedPin = sha256(utf8(`${SALT}\n${SCA_REHEARSAL_PIN}`));

function pinMatches(pin: string) {
  if (!/^\d{6}$/u.test(pin)) return false;
  return constantTimeEqual(sha256(utf8(`${SALT}\n${pin}`)), expectedPin);
}

function canonical(
  binding: ScaPaymentBinding,
  factors: ScaFactor[],
  biometric: BiometricOutcome,
  challengeId: string,
  issuedAt: number,
  nonce: string,
) {
  const fields = [challengeId, binding.recipientId, binding.method, binding.idempotencyKey, nonce];
  if (fields.some((field) => field.length === 0 || field.includes('\n') || field.includes('\r'))) return null;
  if (!Number.isSafeInteger(binding.amountMinor) || binding.amountMinor <= 0) return null;
  return [
    'v1',
    challengeId,
    [...factors].sort().join('+'),
    biometric,
    String(binding.amountMinor),
    binding.recipientId,
    binding.method,
    binding.idempotencyKey,
    String(issuedAt),
    nonce,
    IN_APP_BINDING,
  ].join('\n');
}

export function signScaToken(
  binding: ScaPaymentBinding,
  factors: ScaFactor[],
  biometric: BiometricOutcome,
  challengeId: string,
  issuedAt: number,
  nonce: string,
) {
  const payload = canonical(binding, factors, biometric, challengeId, issuedAt, nonce);
  if (!payload) return null;
  const bytes = utf8(payload);
  return `${bytesToBase64Url(bytes)}.${bytesToBase64Url(hmacSha256(rehearsalKey, bytes))}`;
}

export function authenticatedPayload(token: string) {
  const parts = token.split('.');
  if (parts.length !== 2) return null;
  try {
    const payload = base64UrlToBytes(parts[0]);
    const provided = base64UrlToBytes(parts[1]);
    if (!constantTimeEqual(hmacSha256(rehearsalKey, payload), provided)) return null;
    return new TextDecoder().decode(payload);
  } catch {
    return null;
  }
}

export function verifyScaToken(token: string, binding: ScaPaymentBinding) {
  const payload = authenticatedPayload(token);
  if (!payload) return false;
  const lines = payload.split('\n');
  if (lines.length !== 11 || lines[0] !== 'v1' || !lines[1] || !lines[9]) return false;
  const factors = new Set(lines[2].split('+'));
  const second = factors.has('knowledge') || factors.has('inherence');
  if (!factors.has('possession') || !second) return false;
  if (!['succeeded', 'rejected', 'bypassed', 'unavailable'].includes(lines[3])) return false;
  return (
    lines[4] === String(binding.amountMinor) &&
    lines[5] === binding.recipientId &&
    lines[6] === binding.method &&
    lines[7] === binding.idempotencyKey &&
    lines[10] === IN_APP_BINDING
  );
}

export function hmacHex(key: string, message: string) {
  return hex(hmacSha256(utf8(key), utf8(message)));
}

export function sha256Hex(value: string) {
  return hex(sha256(utf8(value)));
}

function randomNonce() {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return hex(bytes);
}

export function createScaEngine(
  binding: ScaPaymentBinding,
  options?: { challengeId?: string; nonce?: string },
): ScaEngine {
  return {
    binding,
    phase: 'biometric',
    rejectionBanner: null,
    biometric: null,
    entered: '',
    failures: 0,
    lockedUntil: null,
    passcodeMessage: null,
    verification: null,
    challengeId: options?.challengeId ?? crypto.randomUUID(),
    nonce: options?.nonce ?? randomNonce(),
  };
}

export function maskedPasscode(engine: ScaEngine) {
  const filled = Math.min(engine.entered.length, SCA_PIN_LENGTH);
  return `${'•'.repeat(filled)}${'○'.repeat(SCA_PIN_LENGTH - filled)}`;
}

export function secondsLocked(engine: ScaEngine, now: number) {
  if (engine.lockedUntil === null || engine.lockedUntil <= now) return 0;
  return engine.lockedUntil - now;
}

function openPasscode(engine: ScaEngine, biometric: BiometricOutcome, banner: string | null): ScaEngine {
  if (engine.phase !== 'biometric') return engine;
  return { ...engine, phase: 'passcode', biometric, rejectionBanner: banner, entered: '', passcodeMessage: null };
}

export function rejectBiometrics(engine: ScaEngine) {
  return openPasscode(engine, 'rejected', SCA_REJECTION_BANNER);
}

export function bypassBiometrics(engine: ScaEngine) {
  return openPasscode(engine, 'bypassed', null);
}

export function markBiometricsUnavailable(engine: ScaEngine) {
  return openPasscode(engine, 'unavailable', null);
}

function issue(engine: ScaEngine, factors: ScaFactor[], biometric: BiometricOutcome, now: number): ScaEngine {
  const token = signScaToken(engine.binding, factors, biometric, engine.challengeId, now, engine.nonce);
  if (!token) return { ...engine, passcodeMessage: 'Could not complete verification.' };
  const verification: ScaVerification = {
    scaChallengeToken: token,
    factors: [...factors].sort(),
    biometric,
  };
  return {
    ...engine,
    phase: 'verified',
    rejectionBanner: null,
    entered: '',
    failures: 0,
    lockedUntil: null,
    passcodeMessage: null,
    verification,
    biometric,
  };
}

export function succeedBiometrics(engine: ScaEngine, now: number) {
  if (engine.phase !== 'biometric') return engine;
  return issue({ ...engine, biometric: 'succeeded' }, ['possession', 'inherence'], 'succeeded', now);
}

function releaseLock(engine: ScaEngine, now: number): ScaEngine {
  if (engine.lockedUntil !== null && engine.lockedUntil <= now) {
    return { ...engine, lockedUntil: null, failures: 0, passcodeMessage: null };
  }
  return engine;
}

export function appendDigit(engine: ScaEngine, digit: number, now: number): ScaEngine {
  if (engine.phase !== 'passcode' || !Number.isInteger(digit) || digit < 0 || digit > 9) return engine;
  if (engine.lockedUntil !== null && now < engine.lockedUntil) {
    return { ...engine, passcodeMessage: SCA_TOO_MANY_ATTEMPTS };
  }
  const unlocked = releaseLock(engine, now);
  const entered = unlocked.entered + String(digit);
  if (entered.length < SCA_PIN_LENGTH) return { ...unlocked, entered, passcodeMessage: null };
  if (pinMatches(entered)) {
    return issue({ ...unlocked, entered: '' }, ['possession', 'knowledge'], unlocked.biometric ?? 'bypassed', now);
  }
  const failures = unlocked.failures + 1;
  if (failures >= SCA_MAX_ATTEMPTS) {
    return {
      ...unlocked,
      entered: '',
      failures,
      lockedUntil: now + SCA_LOCKOUT_SECONDS,
      passcodeMessage: SCA_TOO_MANY_ATTEMPTS,
    };
  }
  return { ...unlocked, entered: '', failures, passcodeMessage: SCA_INCORRECT_PASSCODE };
}

export function deleteDigit(engine: ScaEngine, now: number): ScaEngine {
  const unlocked = releaseLock(engine, now);
  if (unlocked.phase !== 'passcode' || unlocked.lockedUntil !== null || unlocked.entered.length === 0) return unlocked;
  return { ...unlocked, entered: unlocked.entered.slice(0, -1) };
}

export function rehearsalPaymentBody(input: {
  recipientId: string;
  amountMinor: number;
  method: ScaMethod;
  note: string;
  scenario: string;
}) {
  return {
    recipientId: input.recipientId,
    amountMinor: input.amountMinor,
    method: input.method,
    note: input.note,
    scenario: input.scenario,
  };
}
