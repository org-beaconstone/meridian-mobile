import { describe, expect, it } from 'vitest';
import {
  EXPIRING_THRESHOLD_SECONDS,
  PREVIEW_EXPIRING_SECONDS,
  SESSION_LENGTH_SECONDS,
  applySessionAction,
  formatRemaining,
  presentSession,
  sessionForPhase,
  type PaymentDraft,
  type SessionPhase,
} from './sessionBanner';

const now = 1_700_000_000_000;
const draft: PaymentDraft = {
  recipientId: 'northline-studio',
  amount: '12.50',
  reference: 'Studio deposit',
  method: 'card',
  step: 'review',
  idempotencyKey: 'pay-key-1',
};

describe('session banner', () => {
  it('shows an active session without an action', () => {
    const model = presentSession(sessionForPhase('active', now), now);
    expect(model.phase).toBe('active');
    expect(model.tone).toBe('success');
    expect(model.title).toBe('Session active');
    expect(model.action).toBeNull();
    expect(model.clockLabel).toBeNull();
  });

  it('shows remaining time and a refresh action while expiring', () => {
    const model = presentSession(sessionForPhase('expiring', now), now);
    expect(model.phase).toBe('expiring');
    expect(model.tone).toBe('warning');
    expect(model.action).toBe('refresh');
    expect(model.actionLabel).toBe('Refresh session');
    expect(model.remainingSeconds).toBe(PREVIEW_EXPIRING_SECONDS);
    expect(model.clockLabel).toBe('1:30');
    expect(model.message).toContain('1 minute 30 seconds remaining');
  });

  it('treats the threshold, one second, and elapsed time as separate states', () => {
    expect(
      presentSession({ kind: 'active', expiresAtMs: now + EXPIRING_THRESHOLD_SECONDS * 1000 }, now)
        .phase,
    ).toBe('expiring');
    expect(
      presentSession(
        { kind: 'active', expiresAtMs: now + (EXPIRING_THRESHOLD_SECONDS + 1) * 1000 },
        now,
      ).phase,
    ).toBe('active');
    const oneSecond = presentSession({ kind: 'active', expiresAtMs: now + 1000 }, now);
    expect(oneSecond.clockLabel).toBe('0:01');
    expect(oneSecond.message.startsWith('1 second remaining')).toBe(true);
    const derived = presentSession({ kind: 'active', expiresAtMs: now }, now);
    const explicit = presentSession({ kind: 'expired' }, now);
    expect(derived.title).toBe(explicit.title);
    expect(derived.message).toBe(explicit.message);
    expect(derived.action).toBe('sign-in');
  });

  it('gives every session state its own title and tone', () => {
    const phases: SessionPhase[] = [
      'active',
      'expiring',
      'active-elsewhere',
      'signed-out',
      'expired',
      'unknown',
    ];
    const models = phases.map((phase) => presentSession(sessionForPhase(phase, now), now));
    expect(new Set(models.map((model) => model.title)).size).toBe(6);
    expect(new Set(models.map((model) => model.tone)).size).toBe(6);
    expect(models.find((model) => model.phase === 'signed-out')?.message).toContain(
      'amount, recipient and reference',
    );
    expect(models.find((model) => model.phase === 'unknown')?.message).toContain(
      'payment details stay on this screen',
    );
    expect(models.find((model) => model.phase === 'active-elsewhere')?.message).toContain(
      'Meridian web',
    );
  });

  it('formats remaining time', () => {
    expect(formatRemaining(0)).toBe('0 seconds');
    expect(formatRemaining(2)).toBe('2 seconds');
    expect(formatRemaining(60)).toBe('1 minute');
    expect(formatRemaining(61)).toBe('1 minute 1 second');
    expect(formatRemaining(120)).toBe('2 minutes');
  });

  it('keeps the same payment draft through refresh and recovery', () => {
    const refreshed = applySessionAction(
      sessionForPhase('expiring', now),
      'refresh',
      now,
      true,
      draft,
    );
    expect(refreshed.payment).toBe(draft);
    expect(refreshed.session).toEqual({
      kind: 'active',
      expiresAtMs: now + SESSION_LENGTH_SECONDS * 1000,
    });

    const held = { kind: 'active' as const, expiresAtMs: now + 45_000 };
    const failed = applySessionAction(held, 'refresh', now, false, draft);
    expect(failed.payment).toBe(draft);
    expect(failed.session).toBe(held);

    const signedIn = applySessionAction({ kind: 'expired' }, 'sign-in', now, false, draft);
    expect(signedIn.payment).toBe(draft);
    expect(signedIn.session.kind).toBe('active');

    const offline = applySessionAction({ kind: 'unknown' }, 'try-again', now, false, draft);
    expect(offline.payment).toBe(draft);
    expect(offline.session).toEqual({ kind: 'unknown' });
    expect(offline.announcement).toContain('still here');
  });
});
