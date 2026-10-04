import { useEffect, useRef } from 'react';
import {
  sessionBannerCopy,
  sessionBannerPalette,
  type SessionBannerState,
} from '../domain/sessionStatus';

const glyphs: Record<SessionBannerCopyIndicator, string> = {
  check: 'M4 10.5 7.2 13.5 13 6.5',
  warning: '',
  devices: '',
  'signed-out': '',
};

type SessionBannerCopyIndicator = 'check' | 'warning' | 'devices' | 'signed-out';

function Glyph({ kind }: { kind: SessionBannerCopyIndicator }) {
  if (kind === 'check') {
    return (
      <svg aria-hidden="true" viewBox="0 0 18 18" className="session-glyph">
        <circle cx="9" cy="9" r="7" fill="none" stroke="currentColor" strokeWidth="1.6" />
        <path d={glyphs.check} fill="none" stroke="currentColor" strokeWidth="1.6" />
      </svg>
    );
  }
  if (kind === 'warning') {
    return (
      <svg aria-hidden="true" viewBox="0 0 18 18" className="session-glyph">
        <path d="M9 2.2 16.2 16H1.8Z" fill="none" stroke="currentColor" strokeWidth="1.6" />
        <path d="M9 7.2v3.4" stroke="currentColor" strokeWidth="1.6" />
        <circle cx="9" cy="13.1" r="0.8" fill="currentColor" />
      </svg>
    );
  }
  if (kind === 'devices') {
    return (
      <svg aria-hidden="true" viewBox="0 0 18 18" className="session-glyph">
        <rect x="2" y="4" width="8" height="11" rx="1.2" fill="none" stroke="currentColor" strokeWidth="1.6" />
        <rect x="7" y="2" width="9" height="8" rx="1.2" fill="none" stroke="currentColor" strokeWidth="1.6" />
      </svg>
    );
  }
  return (
    <svg aria-hidden="true" viewBox="0 0 18 18" className="session-glyph">
      <circle cx="9" cy="9" r="7" fill="none" stroke="currentColor" strokeWidth="1.6" />
      <path d="M6 6.2 12 12.2" stroke="currentColor" strokeWidth="1.6" />
    </svg>
  );
}

export function SessionStatusBanner({
  state,
  remainingMillis,
  onRefresh,
}: {
  state: SessionBannerState;
  remainingMillis?: number;
  onRefresh: () => void;
}) {
  const copy = sessionBannerCopy(state, state === 'expiringSoon' ? remainingMillis : undefined);
  const palette = sessionBannerPalette(state);
  return (
    <div className="session-banner-live" role="status" aria-live="polite" aria-atomic="true">
      <button
        type="button"
        className="session-banner"
        data-testid="session-status-banner"
        data-state={state}
        data-background-token={palette.backgroundToken}
        data-foreground-token={palette.foregroundToken}
        aria-label={copy.accessibilityLabel}
        title={copy.accessibilityHint}
        onClick={onRefresh}
        style={{
          backgroundColor: palette.backgroundHex,
          color: palette.foregroundHex,
          borderInlineStartColor: palette.foregroundHex,
        }}
      >
        <Glyph kind={copy.indicator} />
        <span>{copy.message}</span>
      </button>
    </div>
  );
}

export function ReauthenticationDialog({ onContinue }: { onContinue: () => void }) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const buttonRef = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    dialog.showModal();
    buttonRef.current?.focus();
    return () => {
      if (dialog.open) dialog.close();
    };
  }, []);
  return (
    <dialog
      ref={dialogRef}
      className="reauth-modal"
      role="alertdialog"
      aria-labelledby="reauth-title"
      aria-describedby="reauth-copy"
      aria-modal="true"
      onCancel={(event) => event.preventDefault()}
    >
      <h2 id="reauth-title">Session expired</h2>
      <p id="reauth-copy">
        Sign in again to continue this payment. Entered details stay on this screen.
      </p>
      <button ref={buttonRef} type="button" className="primary" onClick={onContinue}>
        Sign in again
      </button>
    </dialog>
  );
}
