import { act, type ReactNode } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { FX_COPY, lockQuote, parseFxQuote } from './domain/fxQuote';
import { RateLockReview } from './RateLockReview';

const lock = lockQuote(
  parseFxQuote({
    quoteId: 'quote-1',
    sourceCurrency: 'GBP',
    targetCurrency: 'EUR',
    sourceAmountMinor: 1250,
    targetAmountMinor: 1463,
    rate: '1.17',
    expiresInSeconds: 60,
  }),
  'GBP',
  'EUR',
  1250,
  Date.parse('2026-10-04T09:00:00.000Z'),
);

describe('Rate lock review', () => {
  let root: Root | null = null;
  let container: HTMLDivElement | null = null;

  afterEach(() => {
    if (root) act(() => root?.unmount());
    container?.remove();
    root = null;
    container = null;
  });

  function render(node: ReactNode) {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
    act(() => root?.render(node));
  }

  it('shows the locked rate and a live 60-second countdown', () => {
    render(<RateLockReview lock={lock} seconds={60} loading={false} error="" onRetry={() => {}} />);
    expect(document.querySelector('[data-testid="locked-rate"]')?.textContent).toContain('1.17');
    const countdown = document.querySelector('[data-testid="rate-lock-countdown"]') as HTMLProgressElement;
    expect(countdown.max).toBe(60);
    expect(countdown.value).toBe(60);
    expect(countdown.getAttribute('aria-valuetext')).toBe('60 seconds remaining');
    expect(document.body.textContent).toContain('Rate locked · 60s');
    expect(document.body.textContent).toContain('€14.63');
  });

  it('prompts an in-place refresh when the lock expires', () => {
    const onRetry = vi.fn();
    render(<RateLockReview lock={lock} seconds={0} loading={false} error="" onRetry={onRetry} />);
    expect(document.body.textContent).toContain(FX_COPY.expired);
    const button = Array.from(document.querySelectorAll('button')).find(
      (item) => item.textContent === FX_COPY.refresh,
    );
    expect(button).toBeTruthy();
    act(() => button?.click());
    expect(onRetry).toHaveBeenCalledOnce();
  });

  it('offers retry guidance when the quote cannot be fetched', () => {
    const onRetry = vi.fn();
    render(
      <RateLockReview lock={null} seconds={0} loading={false} error={FX_COPY.unavailable} onRetry={onRetry} />,
    );
    expect(document.querySelector('[role="alert"]')?.textContent).toBe(FX_COPY.unavailable);
    const button = Array.from(document.querySelectorAll('button')).find(
      (item) => item.textContent === FX_COPY.retry,
    );
    act(() => button?.click());
    expect(onRetry).toHaveBeenCalledOnce();
  });
});
