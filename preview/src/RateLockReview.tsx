import { FX_COPY, formatMinor, type FxQuoteLock } from './domain/fxQuote';

export function RateLockReview({
  lock,
  seconds,
  loading,
  error,
  onRetry,
}: {
  lock: FxQuoteLock | null;
  seconds: number;
  loading: boolean;
  error: string;
  onRetry: () => void;
}) {
  const expired = lock !== null && seconds === 0;
  const showRetry = !loading && (error.length > 0 || expired);
  return (
    <div className="rate-lock" data-testid="rate-lock">
      {loading && lock === null && <p>Locking the exchange rate…</p>}
      {lock && (
        <>
          <p className="rate-lock-rate" data-testid="locked-rate">
            Locked rate {lock.rate} · {lock.sourceCurrency} to {lock.targetCurrency}
          </p>
          {lock.targetAmountMinor !== null && (
            <p>Recipient gets {formatMinor(lock.targetAmountMinor, lock.targetCurrency)}</p>
          )}
          <p data-testid="rate-lock-seconds">{`${FX_COPY.locked} · ${seconds}s`}</p>
          <progress
            data-testid="rate-lock-countdown"
            className={expired ? 'expired' : undefined}
            max={60}
            value={seconds}
            aria-label="Rate lock countdown"
            aria-valuemin={0}
            aria-valuemax={60}
            aria-valuenow={seconds}
            aria-valuetext={`${seconds} seconds remaining`}
          />
        </>
      )}
      {error && (
        <div role="alert" className="error-message">
          {error}
        </div>
      )}
      {expired && !error && (
        <div role="alert" className="error-message">
          {FX_COPY.expired}
        </div>
      )}
      {showRetry && (
        <button type="button" className="secondary" onClick={onRetry}>
          {lock === null ? FX_COPY.retry : FX_COPY.refresh}
        </button>
      )}
    </div>
  );
}
