import {
  type SessionState,
  sessionAccessibilityLabel,
  sessionMessage,
  sessionHasAction,
  sessionActionTitle,
  sessionColorRole,
} from './domain/session';

interface SessionBannerProps {
  state: SessionState;
  onAction?: () => void;
}

/**
 * Persistent, non-blocking session-state banner for the payment screen.
 *
 * Renders four distinct visual states (active, expiring, active-elsewhere,
 * signed-out) aligned with the Figma spec colour tokens. The banner sits
 * above the payment form without covering or disabling any input.
 *
 * Accessibility:
 * - Container carries role="status" and aria-label with the full spoken label
 * - The optional action button has a 44px min-height tap target
 * - Text scales with the browser/OS font-size preference (rem units in CSS)
 */
export function SessionBanner({ state, onAction }: SessionBannerProps) {
  const role = sessionColorRole(state);
  const label = sessionAccessibilityLabel(state);
  const msg = sessionMessage(state);
  const hasAction = sessionHasAction(state);
  const actionTitle = sessionActionTitle(state);

  return (
    <div
      role="status"
      aria-label={label}
      aria-live="polite"
      data-testid="session-banner"
      data-session-state={state.kind}
      className={`session-banner session-banner--${role}`}
    >
      <span className="session-banner__icon" aria-hidden="true">
        {iconForRole(role)}
      </span>
      <span className="session-banner__message">{msg}</span>
      {hasAction && actionTitle && (
        <button
          className="session-banner__action"
          type="button"
          onClick={onAction}
          aria-label={actionTitle}
        >
          {actionTitle}
        </button>
      )}
    </div>
  );
}

function iconForRole(role: string): string {
  switch (role) {
    case 'positive':
      return '✓';
    case 'warning':
      return '⏱';
    case 'information':
      return 'ℹ';
    case 'removed':
      return '!';
    default:
      return '';
  }
}
