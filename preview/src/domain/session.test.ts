import { describe, it, expect } from 'vitest';
import {
  type SessionState,
  sessionAccessibilityLabel,
  sessionMessage,
  sessionHasAction,
  sessionActionTitle,
  sessionColorRole,
  handleSessionAction,
} from './session';

describe('sessionAccessibilityLabel', () => {
  it('active', () => {
    expect(sessionAccessibilityLabel({ kind: 'active' })).toBe('Session active');
  });

  it('expiring – minutes and seconds', () => {
    expect(sessionAccessibilityLabel({ kind: 'expiring', secondsRemaining: 90 })).toBe(
      'Session expiring in 1 minute 30 seconds',
    );
  });

  it('expiring – seconds only', () => {
    expect(sessionAccessibilityLabel({ kind: 'expiring', secondsRemaining: 45 })).toBe(
      'Session expiring in 45 seconds',
    );
  });

  it('expiring – singular second', () => {
    expect(sessionAccessibilityLabel({ kind: 'expiring', secondsRemaining: 1 })).toBe(
      'Session expiring in 1 second',
    );
  });

  it('expiring – singular minute', () => {
    expect(sessionAccessibilityLabel({ kind: 'expiring', secondsRemaining: 61 })).toBe(
      'Session expiring in 1 minute 1 second',
    );
  });

  it('expiring – zero seconds', () => {
    expect(sessionAccessibilityLabel({ kind: 'expiring', secondsRemaining: 0 })).toBe(
      'Session expiring in 0 seconds',
    );
  });

  it('active-elsewhere', () => {
    expect(sessionAccessibilityLabel({ kind: 'active-elsewhere' })).toBe(
      'Session active on another device',
    );
  });

  it('signed-out', () => {
    expect(sessionAccessibilityLabel({ kind: 'signed-out' })).toBe('Session signed out');
  });
});

describe('sessionMessage', () => {
  it('active message is generic confirmation', () => {
    const msg = sessionMessage({ kind: 'active' });
    expect(msg).toBe('Your session is secure and active.');
  });

  it('expiring message contains time and refresh cue', () => {
    const msg = sessionMessage({ kind: 'expiring', secondsRemaining: 120 });
    expect(msg).toContain('2m');
    expect(msg).toContain('Refresh');
  });

  it('expiring message in seconds only', () => {
    const msg = sessionMessage({ kind: 'expiring', secondsRemaining: 30 });
    expect(msg).toContain('30s');
    expect(msg).not.toContain('m ');
  });

  it('active-elsewhere message preserves payment context', () => {
    expect(sessionMessage({ kind: 'active-elsewhere' })).toContain('preserved');
  });

  it('signed-out message preserves payment context', () => {
    expect(sessionMessage({ kind: 'signed-out' })).toContain('preserved');
  });
});

describe('sessionHasAction', () => {
  it('active has no action', () => expect(sessionHasAction({ kind: 'active' })).toBe(false));
  it('expiring has action', () =>
    expect(sessionHasAction({ kind: 'expiring', secondsRemaining: 60 })).toBe(true));
  it('active-elsewhere has action', () =>
    expect(sessionHasAction({ kind: 'active-elsewhere' })).toBe(true));
  it('signed-out has action', () => expect(sessionHasAction({ kind: 'signed-out' })).toBe(true));
});

describe('sessionActionTitle', () => {
  it('active returns null', () => expect(sessionActionTitle({ kind: 'active' })).toBeNull());
  it('expiring returns Refresh', () =>
    expect(sessionActionTitle({ kind: 'expiring', secondsRemaining: 30 })).toBe('Refresh'));
  it('active-elsewhere returns Sign in again', () =>
    expect(sessionActionTitle({ kind: 'active-elsewhere' })).toBe('Sign in again'));
  it('signed-out returns Sign in again', () =>
    expect(sessionActionTitle({ kind: 'signed-out' })).toBe('Sign in again'));
});

describe('sessionColorRole', () => {
  it.each<[SessionState, string]>([
    [{ kind: 'active' }, 'positive'],
    [{ kind: 'expiring', secondsRemaining: 30 }, 'warning'],
    [{ kind: 'active-elsewhere' }, 'information'],
    [{ kind: 'signed-out' }, 'removed'],
  ])('%s → %s', (state, expected) => {
    expect(sessionColorRole(state)).toBe(expected);
  });
});

describe('handleSessionAction', () => {
  it('expiring → active (optimistic refresh)', () => {
    expect(handleSessionAction({ kind: 'expiring', secondsRemaining: 30 })).toEqual({
      kind: 'active',
    });
  });

  it('signed-out → active', () => {
    expect(handleSessionAction({ kind: 'signed-out' })).toEqual({ kind: 'active' });
  });

  it('active-elsewhere → active', () => {
    expect(handleSessionAction({ kind: 'active-elsewhere' })).toEqual({ kind: 'active' });
  });

  it('active → active (no-op)', () => {
    const state: SessionState = { kind: 'active' };
    expect(handleSessionAction(state)).toEqual({ kind: 'active' });
  });
});
