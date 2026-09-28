import { useEffect, useRef } from 'react';
import type { CatalogMethod, PaymentRail } from './domain/paymentRails';

export function PaymentMethodSheet({
  rails,
  selectedMethod,
  onSelect,
  onClose,
}: {
  rails: PaymentRail[];
  selectedMethod: CatalogMethod;
  onSelect: (method: CatalogMethod) => void;
  onClose: () => void;
}) {
  const dialogRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    dialogRef.current?.focus();
    function onKey(event: KeyboardEvent) {
      if (event.key === 'Escape') onClose();
    }
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div className="sheet-root">
      <button
        type="button"
        className="sheet-backdrop"
        aria-label="Close payment methods"
        onClick={onClose}
      />
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="payment-sheet-title"
        tabIndex={-1}
        className="sheet-panel"
      >
        <div className="sheet-handle" aria-hidden="true" />
        <h2 id="payment-sheet-title">Payment method</h2>
        <p className="sheet-note">
          Browser companion for the native bottom sheet. Simulated GBP rehearsal. No real payment is
          sent.
        </p>
        <div role="radiogroup" aria-label="Payment method">
          {rails.map((rail) => (
            <button
              key={rail.id}
              type="button"
              role="radio"
              aria-checked={selectedMethod === rail.method}
              aria-disabled={!rail.selectable}
              aria-label={rail.announcement}
              className={
                'mobile-method' +
                (selectedMethod === rail.method ? ' selected' : '') +
                (rail.selectable ? '' : ' unavailable')
              }
              onClick={() => {
                if (!rail.selectable) return;
                onSelect(rail.method);
              }}
            >
              <span>
                {rail.title}
                <small>{rail.badge}</small>
                {rail.warning && <small className="rail-warning">{rail.warning}</small>}
              </span>
            </button>
          ))}
        </div>
        <button type="button" className="secondary" onClick={onClose}>
          Done
        </button>
      </div>
    </div>
  );
}

export function PaymentMethodSkeletons() {
  return (
    <div
      className="method-skeletons"
      aria-busy="true"
      aria-live="polite"
      aria-label="Loading payment methods"
    >
      <div className="skeleton-card" />
      <div className="skeleton-card" />
    </div>
  );
}
