import { useEffect, useRef } from 'react';
import { railAnnouncement, type PaymentMethodId, type PaymentRail } from './domain/paymentRails';

export default function PaymentMethodSheet({
  method,
  rails,
  onSelect,
  onCommit,
  onClose,
}: {
  method: PaymentMethodId;
  rails: PaymentRail[] | null;
  onSelect: (method: PaymentMethodId) => void;
  onCommit: (method: PaymentMethodId) => void;
  onClose: () => void;
}) {
  const closeRef = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    closeRef.current?.focus();
  }, []);
  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      if (event.key === 'Escape') onClose();
    }
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);

  function move(direction: 1 | -1) {
    if (!rails) return;
    const enabled = rails.filter((rail) => rail.available);
    if (enabled.length === 0) return;
    const current = enabled.findIndex((rail) => rail.method === method);
    const next = enabled[(current + direction + enabled.length) % enabled.length];
    if (next) onSelect(next.method);
  }

  return (
    <div className="sheet-scrim" onClick={onClose}>
      <div
        className="sheet-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="payment-method-title"
        data-testid="payment-method-sheet"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="sheet-handle" aria-hidden="true" />
        <div className="sheet-heading">
          <h2 id="payment-method-title">Payment method</h2>
          <button ref={closeRef} type="button" className="sheet-close" onClick={onClose}>
            Close
          </button>
        </div>
        <p className="sheet-note">Browser companion rehearsal of the native payment sheet.</p>
        {rails === null ? (
          <div aria-busy="true" aria-label="Loading payment methods">
            <div className="rail-skeleton" />
            <div className="rail-skeleton" />
          </div>
        ) : (
          <div
            role="radiogroup"
            aria-label="Payment method"
            onKeyDown={(event) => {
              if (event.key === 'ArrowDown') {
                event.preventDefault();
                move(1);
              }
              if (event.key === 'ArrowUp') {
                event.preventDefault();
                move(-1);
              }
            }}
          >
            {rails.map((rail, index) => (
              <button
                key={rail.method}
                type="button"
                role="radio"
                aria-checked={method === rail.method}
                aria-disabled={!rail.available}
                aria-label={railAnnouncement(rail, index + 1, rails.length)}
                className={
                  'mobile-method' +
                  (method === rail.method ? ' selected' : '') +
                  (rail.available ? '' : ' unavailable')
                }
                onClick={() => {
                  if (rail.available) onCommit(rail.method);
                }}
              >
                <span className="rail-mark" aria-hidden="true" />
                <span>
                  {rail.badge}
                  {rail.warning ? <small className="rail-warning">{rail.warning}</small> : null}
                </span>
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
