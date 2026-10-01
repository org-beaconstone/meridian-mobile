export const SESSION_LENGTH_SECONDS = 600;
export const EXPIRING_THRESHOLD_SECONDS = 120;
export const PREVIEW_EXPIRING_SECONDS = 90;

export type SessionPhase =
  'active' | 'expiring' | 'active-elsewhere' | 'signed-out' | 'expired' | 'unknown';

export type SessionTone =
  'success' | 'warning' | 'information' | 'neutral' | 'danger' | 'attention';

export type SessionAction = 'refresh' | 'sign-in' | 'continue-here' | 'try-again';

export type CustomerSession =
  | { kind: 'active'; expiresAtMs: number }
  | { kind: 'active-elsewhere'; deviceName: string }
  | { kind: 'signed-out' }
  | { kind: 'expired' }
  | { kind: 'unknown' };

export type PaymentDraft = {
  recipientId: string;
  amount: string;
  reference: string;
  method: 'card' | 'bank';
  step: 'details' | 'review' | 'done';
  idempotencyKey: string;
};

export type SessionBannerModel = {
  phase: SessionPhase;
  tone: SessionTone;
  title: string;
  message: string;
  clockLabel: string | null;
  remainingSeconds: number | null;
  action: SessionAction | null;
  actionLabel: string | null;
  accessibilityLabel: string;
};

export type SessionUpdate = {
  session: CustomerSession;
  announcement: string;
  payment: PaymentDraft;
};

const ACTION_LABEL: Record<SessionAction, string> = {
  refresh: 'Refresh session',
  'sign-in': 'Sign in',
  'continue-here': 'Continue here',
  'try-again': 'Try again',
};

export function formatRemaining(totalSeconds: number): string {
  const seconds = Math.max(0, Math.floor(totalSeconds));
  const minutes = Math.floor(seconds / 60);
  const rest = seconds % 60;
  const parts: string[] = [];
  if (minutes > 0) parts.push(`${minutes} ${minutes === 1 ? 'minute' : 'minutes'}`);
  if (rest > 0 || minutes === 0) parts.push(`${rest} ${rest === 1 ? 'second' : 'seconds'}`);
  return parts.join(' ');
}

export function formatClock(totalSeconds: number): string {
  const seconds = Math.max(0, Math.floor(totalSeconds));
  const minutes = Math.floor(seconds / 60);
  const rest = seconds % 60;
  return `${minutes}:${rest.toString().padStart(2, '0')}`;
}

export function sessionForPhase(
  phase: SessionPhase,
  nowMs: number,
  deviceName = 'Meridian web',
): CustomerSession {
  switch (phase) {
    case 'active':
      return { kind: 'active', expiresAtMs: nowMs + SESSION_LENGTH_SECONDS * 1000 };
    case 'expiring':
      return { kind: 'active', expiresAtMs: nowMs + PREVIEW_EXPIRING_SECONDS * 1000 };
    case 'active-elsewhere':
      return { kind: 'active-elsewhere', deviceName };
    case 'signed-out':
      return { kind: 'signed-out' };
    case 'expired':
      return { kind: 'expired' };
    case 'unknown':
      return { kind: 'unknown' };
  }
}

export function presentSession(session: CustomerSession, nowMs: number): SessionBannerModel {
  switch (session.kind) {
    case 'active': {
      const remaining = remainingWholeSeconds(session.expiresAtMs, nowMs);
      if (remaining <= 0) return expiredBanner();
      if (remaining <= EXPIRING_THRESHOLD_SECONDS) return expiringBanner(remaining);
      return activeBanner();
    }
    case 'active-elsewhere':
      return elsewhereBanner(session.deviceName);
    case 'signed-out':
      return signedOutBanner();
    case 'expired':
      return expiredBanner();
    case 'unknown':
      return unknownBanner();
  }
}

export function applySessionAction(
  session: CustomerSession,
  action: SessionAction,
  nowMs: number,
  apiReachable: boolean,
  payment: PaymentDraft,
): SessionUpdate {
  const renewed: CustomerSession = {
    kind: 'active',
    expiresAtMs: nowMs + SESSION_LENGTH_SECONDS * 1000,
  };
  switch (action) {
    case 'refresh':
      return apiReachable
        ? {
            session: renewed,
            announcement: 'Session refreshed. Payment details are unchanged.',
            payment,
          }
        : {
            session,
            announcement: "Couldn't refresh the session. Your payment details are still here.",
            payment,
          };
    case 'sign-in':
      return {
        session: renewed,
        announcement: 'Signed in on this device. Payment details are unchanged.',
        payment,
      };
    case 'continue-here':
      return {
        session: renewed,
        announcement: 'Continuing on this device. Payment details are unchanged.',
        payment,
      };
    case 'try-again':
      return apiReachable
        ? {
            session: renewed,
            announcement: 'Session confirmed. Payment details are unchanged.',
            payment,
          }
        : {
            session: { kind: 'unknown' },
            announcement:
              "We still couldn't confirm this session. Your payment details are still here.",
            payment,
          };
  }
}

function remainingWholeSeconds(expiresAtMs: number, nowMs: number): number {
  const delta = expiresAtMs - nowMs;
  if (delta <= 0) return 0;
  return Math.floor(delta / 1000);
}

function model(
  phase: SessionPhase,
  tone: SessionTone,
  title: string,
  message: string,
  extras: Partial<Pick<SessionBannerModel, 'clockLabel' | 'remainingSeconds' | 'action'>> = {},
): SessionBannerModel {
  const action = extras.action ?? null;
  return {
    phase,
    tone,
    title,
    message,
    clockLabel: extras.clockLabel ?? null,
    remainingSeconds: extras.remainingSeconds ?? null,
    action,
    actionLabel: action ? ACTION_LABEL[action] : null,
    accessibilityLabel: `${title}. ${message}`,
  };
}

function activeBanner(): SessionBannerModel {
  return model(
    'active',
    'success',
    'Session active',
    'Signed in on this device. You can keep entering this payment.',
  );
}

function expiringBanner(remaining: number): SessionBannerModel {
  const spoken = formatRemaining(remaining);
  return model(
    'expiring',
    'warning',
    'Session expiring',
    `${spoken} remaining. Refresh to stay signed in. This payment stays on screen.`,
    { clockLabel: formatClock(remaining), remainingSeconds: remaining, action: 'refresh' },
  );
}

function elsewhereBanner(deviceName: string): SessionBannerModel {
  return model(
    'active-elsewhere',
    'information',
    'Active on another device',
    `Signed in on ${displayDevice(deviceName)}. Continue here when you are ready. Entered payment details stay on this screen.`,
    { action: 'continue-here' },
  );
}

function signedOutBanner(): SessionBannerModel {
  return model(
    'signed-out',
    'neutral',
    'Signed out',
    'Sign in again to send this payment. The amount, recipient and reference you entered are kept.',
    { action: 'sign-in' },
  );
}

function expiredBanner(): SessionBannerModel {
  return model(
    'expired',
    'danger',
    'Session expired',
    'Your sign-in has expired. Sign in again to continue. Entered payment details are still here.',
    { action: 'sign-in' },
  );
}

function unknownBanner(): SessionBannerModel {
  return model(
    'unknown',
    'attention',
    'Session unknown',
    "We couldn't confirm this session. Try again when you are ready. Your payment details stay on this screen.",
    { action: 'try-again' },
  );
}

function displayDevice(name: string): string {
  const trimmed = name.trim().replace(/\s+/g, ' ');
  if (!trimmed) return 'another device';
  return trimmed.length <= 40 ? trimmed : trimmed.slice(0, 40);
}
