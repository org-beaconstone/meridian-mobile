/**
 * All valid states a payment-screen session banner can display.
 *
 * The union maps to the four states defined in the Figma spec:
 * - `active`           – session confirmed valid
 * - `expiring`         – session close to expiry; secondsRemaining drives the countdown
 * - `active-elsewhere` – session live on another device
 * - `signed-out`       – session has been terminated
 *
 * Recovery states preserve entered payment context by design:
 * they are non-blocking and must not clear form fields.
 */
export type SessionState =
  | { kind: 'active' }
  | { kind: 'expiring'; secondsRemaining: number }
  | { kind: 'active-elsewhere' }
  | { kind: 'signed-out' };

/** Short label used for aria-label and screen-reader announcements. */
export function sessionAccessibilityLabel(state: SessionState): string {
  switch (state.kind) {
    case 'active':
      return 'Session active';
    case 'expiring': {
      const mins = Math.floor(state.secondsRemaining / 60);
      const secs = state.secondsRemaining % 60;
      if (mins > 0) {
        return `Session expiring in ${mins} minute${mins === 1 ? '' : 's'} ${secs} second${secs === 1 ? '' : 's'}`;
      }
      return `Session expiring in ${state.secondsRemaining} second${state.secondsRemaining === 1 ? '' : 's'}`;
    }
    case 'active-elsewhere':
      return 'Session active on another device';
    case 'signed-out':
      return 'Session signed out';
  }
}

/** Body text displayed inside the banner. */
export function sessionMessage(state: SessionState): string {
  switch (state.kind) {
    case 'active':
      return 'Your session is secure and active.';
    case 'expiring': {
      const mins = Math.floor(state.secondsRemaining / 60);
      const secs = state.secondsRemaining % 60;
      const time = mins > 0 ? `${mins}m ${secs}s` : `${state.secondsRemaining}s`;
      return `Session expiring in ${time}. Tap Refresh to stay signed in.`;
    }
    case 'active-elsewhere':
      return 'Your session is active on another device. Your payment details are preserved. Sign in again to continue.';
    case 'signed-out':
      return 'You have been signed out. Your payment details are preserved. Sign in again to continue.';
  }
}

/** Whether this state offers a primary action button. */
export function sessionHasAction(state: SessionState): boolean {
  return state.kind !== 'active';
}

/** The action button label, or `null` when there is no action. */
export function sessionActionTitle(state: SessionState): string | null {
  switch (state.kind) {
    case 'active':
      return null;
    case 'expiring':
      return 'Refresh';
    case 'active-elsewhere':
    case 'signed-out':
      return 'Sign in again';
  }
}

/**
 * Semantic colour role token for the banner.
 * Values: 'positive' | 'warning' | 'information' | 'removed'
 */
export function sessionColorRole(
  state: SessionState,
): 'positive' | 'warning' | 'information' | 'removed' {
  switch (state.kind) {
    case 'active':
      return 'positive';
    case 'expiring':
      return 'warning';
    case 'active-elsewhere':
      return 'information';
    case 'signed-out':
      return 'removed';
  }
}

/**
 * Returns the next `SessionState` after the user taps the banner action.
 * Optimistically assumes re-auth / token-refresh succeeded.
 * Payment context (amount, recipient, reference) is not touched here.
 */
export function handleSessionAction(current: SessionState): SessionState {
  if (current.kind === 'active') return current;
  return { kind: 'active' };
}
