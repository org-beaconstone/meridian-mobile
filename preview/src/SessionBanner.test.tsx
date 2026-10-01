import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { SessionBanner } from './SessionBanner';
import {
  applySessionAction,
  presentSession,
  sessionForPhase,
  type CustomerSession,
  type PaymentDraft,
  type SessionAction,
} from './domain/sessionBanner';

describe('session banner element', () => {
  let root: Root | null = null;
  let host: HTMLDivElement;

  beforeEach(() => {
    host = document.createElement('div');
    document.body.appendChild(host);
  });

  afterEach(() => {
    act(() => root?.unmount());
    root = null;
    host.remove();
  });

  function render(
    session: CustomerSession,
    nowMs: number,
    onAction: (action: SessionAction) => void = () => {},
  ) {
    act(() => {
      root ??= createRoot(host);
      root.render(<SessionBanner model={presentSession(session, nowMs)} onAction={onAction} />);
    });
  }

  it('renders each visual state with an accessible action outside a form submit', () => {
    const now = 1_700_000_000_000;
    const cases = [
      ['active', null],
      ['expiring', 'Refresh session'],
      ['active-elsewhere', 'Continue here'],
      ['signed-out', 'Sign in'],
      ['expired', 'Sign in'],
      ['unknown', 'Try again'],
    ] as const;
    const tones = new Set<string>();
    for (const [phase, action] of cases) {
      render(sessionForPhase(phase, now), now);
      const banner = host.querySelector('[data-testid="session-banner"]');
      expect(banner?.getAttribute('data-tone')).toBeTruthy();
      tones.add(banner?.getAttribute('data-tone') || '');
      expect(banner?.querySelector('h2')?.textContent).toBeTruthy();
      const button = banner?.querySelector('button');
      if (action) {
        expect(button?.textContent).toBe(action);
        expect(button?.getAttribute('type')).toBe('button');
      } else {
        expect(button).toBeNull();
      }
      expect(banner?.querySelector('.session-clock')?.getAttribute('aria-hidden')).toBe(
        phase === 'expiring' ? 'true' : undefined,
      );
    }
    expect(tones.size).toBe(6);
  });

  it('refresh reports the same payment draft and does not submit a form', () => {
    const now = 1_700_000_000_000;
    const draft: PaymentDraft = {
      recipientId: 'northline-studio',
      amount: '12.50',
      reference: 'Studio deposit',
      method: 'card',
      step: 'review',
      idempotencyKey: 'pay-key-1',
    };
    const seen: PaymentDraft[] = [];
    render(sessionForPhase('expiring', now), now, (action) => {
      seen.push(
        applySessionAction(sessionForPhase('expiring', now), action, now, true, draft).payment,
      );
    });
    const button = host.querySelector('button');
    act(() => {
      button?.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    });
    expect(seen).toEqual([draft]);
    expect(draft).toMatchObject({
      amount: '12.50',
      reference: 'Studio deposit',
      idempotencyKey: 'pay-key-1',
      step: 'review',
    });
  });
});
