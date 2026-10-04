import { useEffect, useState } from 'react';
import {
  SCA_BIOMETRICS_UNAVAILABLE,
  SCA_REHEARSAL_PIN,
  SCA_TOO_MANY_ATTEMPTS,
  type ScaEngine,
  type ScaVerification,
  appendDigit,
  bypassBiometrics,
  deleteDigit,
  markBiometricsUnavailable,
  maskedPasscode,
  rejectBiometrics,
  secondsLocked,
} from './domain/sca';

type Props = {
  engine: ScaEngine;
  now?: number;
  onChange: (engine: ScaEngine) => void;
  onCancel: () => void;
  onVerified: (verification: ScaVerification) => void;
};

export function ScaSheet({ engine, now: nowProp, onChange, onCancel, onVerified }: Props) {
  const [tick, setTick] = useState(0);
  useEffect(() => {
    if (engine.lockedUntil === null) return undefined;
    const id = window.setInterval(() => setTick((value) => value + 1), 1000);
    return () => window.clearInterval(id);
  }, [engine.lockedUntil]);
  const now = nowProp ?? Math.floor(Date.now() / 1000);
  // tick forces a fresh clock reading while the keypad is locked.
  void tick;
  const locked = secondsLocked(engine, now);
  function update(next: ScaEngine) {
    onChange(next);
    if (next.verification) onVerified(next.verification);
  }
  const digits = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9],
  ];
  return (
    <section className="sca-sheet" data-testid="sca-sheet" aria-label="In-app security challenge">
      <p className="sca-companion">
        Browser companion rehearsal of the in-app SCA sheet. This is not the iOS or Android binary
        and does not call a payment provider.
      </p>
      <h2>{engine.phase === 'biometric' ? "Confirm it's you" : 'Security passcode'}</h2>
      <p>Possession plus a second factor stay inside Meridian. This check does not leave the app.</p>
      {engine.phase === 'biometric' ? (
        <>
          <button className="primary" type="button" onClick={() => update(markBiometricsUnavailable(engine))}>
            Verify with biometrics
          </button>
          <button className="secondary" type="button" onClick={() => update(rejectBiometrics(engine))}>
            Reject biometrics
          </button>
          <button className="secondary" type="button" onClick={() => update(bypassBiometrics(engine))}>
            Use passcode instead
          </button>
        </>
      ) : (
        <>
          {engine.rejectionBanner && (
            <div role="alert" className="error-message" data-testid="sca-banner">
              {engine.rejectionBanner}
            </div>
          )}
          {engine.biometric === 'unavailable' && !engine.rejectionBanner && (
            <p>{SCA_BIOMETRICS_UNAVAILABLE}</p>
          )}
          <div
            className="sca-dots"
            data-testid="sca-dots"
            aria-label={`${engine.entered.length} of 6 digits entered`}
          >
            {maskedPasscode(engine)}
          </div>
          {locked > 0 ? (
            <p role="status">
              {SCA_TOO_MANY_ATTEMPTS} {locked}s remaining.
            </p>
          ) : (
            engine.passcodeMessage && <p role="status">{engine.passcodeMessage}</p>
          )}
          <div className="sca-keypad">
            {digits.flat().map((digit) => (
              <button
                key={digit}
                type="button"
                disabled={locked > 0}
                onClick={() => update(appendDigit(engine, digit, now))}
              >
                {digit}
              </button>
            ))}
            <span />
            <button type="button" disabled={locked > 0} onClick={() => update(appendDigit(engine, 0, now))}>
              0
            </button>
            <button type="button" disabled={locked > 0} onClick={() => update(deleteDigit(engine, now))}>
              Delete
            </button>
          </div>
          <p className="fine-print">
            Fictional rehearsal passcode: {SCA_REHEARSAL_PIN}. It stays in this browser session and
            is not sent to the API.
          </p>
        </>
      )}
      <button className="secondary" type="button" onClick={onCancel}>
        Cancel
      </button>
    </section>
  );
}
