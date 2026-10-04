/** Keep aligned with SessionStatus.swift and SessionStatus.kt. Browser companion only. */

export const SESSION_WARNING_WINDOW_MS = 5 * 60 * 1000;
export const PAYMENT_SESSION_TTL_MS = 15 * 60 * 1000;
export const SESSION_EXPIRING_MESSAGE = 'Session expiring soon. Tap to extend.';

export type SessionPresence = 'here' | 'elsewhere' | 'signedOut';
export type SessionBannerState = 'active' | 'expiringSoon' | 'activeElsewhere' | 'signedOut';
export type SessionPhase =
  | { kind: 'banner'; state: SessionBannerState }
  | { kind: 'reauthenticate' };

export type PaymentDraft = {
  recipientId: string;
  amount: string;
  reference: string;
  method: 'card' | 'bank';
  reviewing: boolean;
  idempotencyKey: string;
};

export type PaymentSessionClock = {
  presence: SessionPresence;
  expiresAt: number;
};

export type SessionBannerCopy = {
  message: string;
  accessibilityLabel: string;
  accessibilityHint: string;
  indicator: 'check' | 'warning' | 'devices' | 'signed-out';
};

export type SessionBannerPalette = {
  backgroundHex: string;
  foregroundHex: string;
  backgroundToken: string;
  foregroundToken: string;
};

export function sessionPhase(
  presence: SessionPresence,
  expiresAt: number,
  now: number,
): SessionPhase {
  if (presence === 'signedOut') return { kind: 'banner', state: 'signedOut' };
  if (now >= expiresAt) return { kind: 'reauthenticate' };
  const remaining = expiresAt - now;
  if (remaining < SESSION_WARNING_WINDOW_MS) return { kind: 'banner', state: 'expiringSoon' };
  if (presence === 'elsewhere') return { kind: 'banner', state: 'activeElsewhere' };
  return { kind: 'banner', state: 'active' };
}

export function sessionRequiresReauthentication(
  presence: SessionPresence,
  expiresAt: number,
  now: number,
): boolean {
  return sessionPhase(presence, expiresAt, now).kind === 'reauthenticate';
}

export function sessionRemainingDescription(remainingMillis: number): string {
  const seconds = Math.max(0, Math.floor(remainingMillis / 1000));
  const minutes = Math.floor(seconds / 60);
  const rest = seconds % 60;
  if (minutes > 0 && rest === 0) return minutes === 1 ? '1 minute' : `${minutes} minutes`;
  if (minutes > 0) return `${minutes} minutes ${rest} seconds`;
  return `${seconds} seconds`;
}

export function sessionBannerCopy(
  state: SessionBannerState,
  remainingMillis?: number,
): SessionBannerCopy {
  const accessibilityHint =
    'Refreshes the session in place and keeps the payment details you entered.';
  switch (state) {
    case 'active':
      return {
        message: 'Session active.',
        accessibilityLabel: 'Session active.',
        accessibilityHint,
        indicator: 'check',
      };
    case 'expiringSoon': {
      const suffix =
        remainingMillis === undefined
          ? ''
          : ` ${sessionRemainingDescription(remainingMillis)} remaining.`;
      return {
        message: SESSION_EXPIRING_MESSAGE,
        accessibilityLabel: SESSION_EXPIRING_MESSAGE + suffix,
        accessibilityHint,
        indicator: 'warning',
      };
    }
    case 'activeElsewhere':
      return {
        message: 'Session active on another device.',
        accessibilityLabel: 'Session active on another device.',
        accessibilityHint,
        indicator: 'devices',
      };
    case 'signedOut':
      return {
        message: 'Signed out.',
        accessibilityLabel: 'Signed out.',
        accessibilityHint,
        indicator: 'signed-out',
      };
  }
}

export function sessionBannerPalette(state: SessionBannerState): SessionBannerPalette {
  switch (state) {
    case 'active':
      return {
        backgroundHex: '#EFFFD6',
        foregroundHex: '#4C6B1F',
        backgroundToken: 'color.background.success',
        foregroundToken: 'color.text.success',
      };
    case 'expiringSoon':
      return {
        backgroundHex: '#FFF5DB',
        foregroundHex: '#9E4C00',
        backgroundToken: 'color.background.warning',
        foregroundToken: 'color.text.warning',
      };
    case 'activeElsewhere':
      return {
        backgroundHex: '#E9F2FE',
        foregroundHex: '#1558BC',
        backgroundToken: 'color.background.information',
        foregroundToken: 'color.text.information',
      };
    case 'signedOut':
      return {
        backgroundHex: '#FFECEB',
        foregroundHex: '#AE2E24',
        backgroundToken: 'color.background.danger',
        foregroundToken: 'color.text.danger',
      };
  }
}

export function contrastRatio(foregroundHex: string, backgroundHex: string): number {
  const luminance = (hex: string) => {
    const channels = hex
      .replace('#', '')
      .match(/../g)!
      .map((part) => {
        const channel = parseInt(part, 16) / 255;
        return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
      });
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
  };
  const lighter = Math.max(luminance(foregroundHex), luminance(backgroundHex));
  const darker = Math.min(luminance(foregroundHex), luminance(backgroundHex));
  return (lighter + 0.05) / (darker + 0.05);
}

export function refreshSessionInPlace(
  draft: PaymentDraft,
  _session: PaymentSessionClock,
  now: number,
  ttl = PAYMENT_SESSION_TTL_MS,
): { draft: PaymentDraft; session: PaymentSessionClock } {
  return {
    draft,
    session: { presence: 'here', expiresAt: now + ttl },
  };
}

export function sessionOverrideFromQuery(value: string | null): SessionPhase | null {
  switch (value) {
    case 'active':
      return { kind: 'banner', state: 'active' };
    case 'expiring':
      return { kind: 'banner', state: 'expiringSoon' };
    case 'elsewhere':
      return { kind: 'banner', state: 'activeElsewhere' };
    case 'signed-out':
      return { kind: 'banner', state: 'signedOut' };
    case 'expired':
      return { kind: 'reauthenticate' };
    default:
      return null;
  }
}
