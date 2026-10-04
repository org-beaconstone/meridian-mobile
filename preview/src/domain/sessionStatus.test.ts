import { describe, expect, it } from 'vitest';
import {
  PAYMENT_SESSION_TTL_MS,
  SESSION_EXPIRING_MESSAGE,
  SESSION_WARNING_WINDOW_MS,
  contrastRatio,
  refreshSessionInPlace,
  sessionBannerCopy,
  sessionBannerPalette,
  sessionOverrideFromQuery,
  sessionPhase,
  sessionRequiresReauthentication,
  type PaymentDraft,
  type SessionBannerState,
} from './sessionStatus';

const now = 1_700_000_000_000;

describe('payment session status', () => {
  it('keeps a full five minutes active', () => {
    expect(sessionPhase('here', now + SESSION_WARNING_WINDOW_MS, now)).toEqual({
      kind: 'banner',
      state: 'active',
    });
    expect(sessionRequiresReauthentication('here', now + SESSION_WARNING_WINDOW_MS, now)).toBe(
      false,
    );
  });

  it('warns under five minutes without blocking', () => {
    expect(sessionPhase('here', now + SESSION_WARNING_WINDOW_MS - 1, now)).toEqual({
      kind: 'banner',
      state: 'expiringSoon',
    });
    expect(sessionRequiresReauthentication('here', now + 4 * 60 * 1000, now)).toBe(false);
    const copy = sessionBannerCopy('expiringSoon', 4 * 60 * 1000);
    expect(copy.message).toBe(SESSION_EXPIRING_MESSAGE);
    expect(copy.accessibilityLabel).toBe(
      'Session expiring soon. Tap to extend. 4 minutes remaining.',
    );
    expect(copy.indicator).toBe('warning');
    const palette = sessionBannerPalette('expiringSoon');
    expect(palette.backgroundToken).toBe('color.background.warning');
    expect(palette.foregroundToken).toBe('color.text.warning');
  });

  it('opens re-authentication only when the session has fully elapsed', () => {
    expect(sessionRequiresReauthentication('here', now, now)).toBe(true);
    expect(sessionRequiresReauthentication('elsewhere', now - 1, now)).toBe(true);
    expect(sessionRequiresReauthentication('signedOut', now - 60_000, now)).toBe(false);
    expect(sessionPhase('signedOut', now - 60_000, now)).toEqual({
      kind: 'banner',
      state: 'signedOut',
    });
  });

  it('shows elsewhere, then the warning when that session is inside five minutes', () => {
    expect(sessionPhase('elsewhere', now + 10 * 60 * 1000, now)).toEqual({
      kind: 'banner',
      state: 'activeElsewhere',
    });
    expect(sessionPhase('elsewhere', now + 60_000, now)).toEqual({
      kind: 'banner',
      state: 'expiringSoon',
    });
    expect(sessionBannerCopy('active').message).toBe('Session active.');
    expect(sessionBannerCopy('activeElsewhere').message).toBe('Session active on another device.');
    expect(sessionBannerCopy('signedOut').indicator).toBe('signed-out');
  });

  it('refreshes in place without clearing the payment draft', () => {
    const draft: PaymentDraft = {
      recipientId: 'northline-studio',
      amount: '18.25',
      reference: 'Studio rent',
      method: 'bank',
      reviewing: true,
      idempotencyKey: 'pay-key-171',
    };
    const refreshed = refreshSessionInPlace(
      draft,
      { presence: 'elsewhere', expiresAt: now + 30_000 },
      now,
    );
    expect(refreshed.draft).toEqual(draft);
    expect(refreshed.session).toEqual({ presence: 'here', expiresAt: now + PAYMENT_SESSION_TTL_MS });
  });

  it('meets 4.5:1 contrast for every banner state', () => {
    const warning = contrastRatio('#9E4C00', '#FFF5DB');
    expect(warning).toBeGreaterThanOrEqual(4.5);
    expect(warning).toBeLessThan(6);
    const states: SessionBannerState[] = ['active', 'expiringSoon', 'activeElsewhere', 'signedOut'];
    for (const state of states) {
      const palette = sessionBannerPalette(state);
      expect(contrastRatio(palette.foregroundHex, palette.backgroundHex)).toBeGreaterThanOrEqual(4.5);
    }
  });

  it('reads rehearsal query overrides', () => {
    expect(sessionOverrideFromQuery('expiring')).toEqual({ kind: 'banner', state: 'expiringSoon' });
    expect(sessionOverrideFromQuery('expired')).toEqual({ kind: 'reauthenticate' });
    expect(sessionOverrideFromQuery('nope')).toBeNull();
  });
});
