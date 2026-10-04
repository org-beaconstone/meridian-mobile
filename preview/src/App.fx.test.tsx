import { act, type ReactNode } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, describe, expect, it, vi } from 'vitest';
import App from './App';
import { FX_COPY } from './domain/fxQuote';

const state = {
  version: 1,
  balance: 1248050,
  transactions: [],
  budgets: [{ category: 'Shopping', limit: 100000 }],
};
const catalog = {
  demoDate: '2026-09-18',
  recipients: [
    {
      id: 'northline-studio',
      name: 'Northline Studio',
      category: 'Shopping',
      initials: 'NS',
      detail: 'Design',
    },
  ],
  providers: [],
};

function json(status: number, body: unknown) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  };
}

describe('FX review in the browser companion', () => {
  let root: Root | null = null;
  let container: HTMLDivElement | null = null;
  const calls: { url: string; body?: unknown; key?: string }[] = [];

  afterEach(() => {
    if (root) act(() => root?.unmount());
    container?.remove();
    root = null;
    container = null;
    vi.unstubAllGlobals();
  });

  async function render(node: ReactNode) {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
    await act(async () => {
      root?.render(node);
    });
  }

  async function waitFor(predicate: () => boolean) {
    const start = Date.now();
    while (Date.now() - start < 2500) {
      if (predicate()) return;
      await act(async () => {
        await new Promise((resolve) => setTimeout(resolve, 20));
      });
    }
    throw new Error(`Timed out. Body: ${document.body.textContent}`);
  }

  async function setControl(id: string, value: string) {
    const element = document.getElementById(id) as HTMLInputElement | HTMLSelectElement;
    await act(async () => {
      const prototype = Object.getPrototypeOf(element);
      const descriptor = Object.getOwnPropertyDescriptor(prototype, 'value');
      descriptor?.set?.call(element, value);
      element.dispatchEvent(new Event('input', { bubbles: true }));
      element.dispatchEvent(new Event('change', { bubbles: true }));
    });
  }

  function click(name: string) {
    const button = Array.from(document.querySelectorAll('button')).find((item) => item.textContent === name);
    if (!button) throw new Error(`Missing button ${name}`);
    return act(async () => {
      button.click();
    });
  }

  function installFetch(quoteResponses: Array<{ status: number; body: unknown }>) {
    let quoteIndex = 0;
    calls.length = 0;
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string, init?: RequestInit) => {
        const path = String(url);
        const body = init?.body ? JSON.parse(String(init.body)) : undefined;
        const headers = new Headers(init?.headers);
        calls.push({ url: path, body, key: headers.get('Idempotency-Key') ?? undefined });
        if (path.endsWith('/state')) return json(200, state);
        if (path.endsWith('/catalog')) return json(200, catalog);
        if (path.endsWith('/fx/quote')) {
          const next = quoteResponses[Math.min(quoteIndex, quoteResponses.length - 1)];
          quoteIndex += 1;
          return json(next.status, next.body);
        }
        if (path.endsWith('/payments')) {
          return json(200, {
            ok: true,
            state: { ...state, balance: state.balance - (body?.amountMinor ?? 0) },
            transaction: {
              id: 'txn-1',
              name: 'Northline Studio',
              amount: body?.amountMinor,
              date: '2026-10-04',
              category: 'Shopping',
              status: 'completed',
              provider: 'adyen',
              reference: 'REF-1',
            },
          });
        }
        return json(404, { error: 'missing' });
      }),
    );
  }

  const liveQuote = {
    quoteId: 'quote-1',
    sourceCurrency: 'GBP',
    targetCurrency: 'EUR',
    sourceAmountMinor: 1250,
    targetAmountMinor: 1463,
    rate: '1.17',
    expiresInSeconds: 60,
  };

  it('locks a EUR rate, counts down, and submits the quote id without resetting the draft', async () => {
    installFetch([
      { status: 503, body: { error: 'unavailable', code: 'FX_UNAVAILABLE' } },
      { status: 200, body: { ...liveQuote, expiresInSeconds: 0, quoteId: 'quote-expired' } },
      { status: 200, body: { ...liveQuote, quoteId: 'quote-fresh' } },
    ]);
    await render(<App />);
    await waitFor(() => document.querySelector('[data-testid="mobile-balance"]') !== null);
    await click('Pay');
    await setControl('mobile-amount', '12.50');
    await setControl('mobile-note', 'Studio invoice');
    await setControl('mobile-currency', 'EUR');
    await click('Review payment');
    await waitFor(() => document.body.textContent?.includes(FX_COPY.unavailable) === true);
    expect(calls.filter((call) => call.url.endsWith('/fx/quote'))[0]?.body).toEqual({
      sourceCurrency: 'GBP',
      targetCurrency: 'EUR',
      amountMinor: 1250,
    });
    await click(FX_COPY.retry);
    await waitFor(() => document.body.textContent?.includes(FX_COPY.expired) === true);
    const review = document.querySelector('[data-testid="payment-review"]');
    const key = review?.getAttribute('data-idempotency-key');
    const confirm = Array.from(document.querySelectorAll('button')).find(
      (item) => item.textContent === 'Confirm payment',
    ) as HTMLButtonElement;
    expect(confirm.disabled).toBe(true);
    await click(FX_COPY.refresh);
    await waitFor(() => document.querySelector('[data-testid="locked-rate"]')?.textContent?.includes('1.17') === true);
    expect(document.querySelector('[data-testid="rate-lock-countdown"]')).toBeTruthy();
    expect(document.querySelector('[data-testid="payment-review"]')?.getAttribute('data-idempotency-key')).toBe(key);
    await click('Back to details');
    expect((document.getElementById('mobile-amount') as HTMLInputElement).value).toBe('12.50');
    expect((document.getElementById('mobile-note') as HTMLInputElement).value).toBe('Studio invoice');
    expect((document.getElementById('mobile-currency') as HTMLSelectElement).value).toBe('EUR');
    await click('Review payment');
    await waitFor(() => document.querySelector('[data-testid="locked-rate"]') !== null);
    await click('Confirm payment');
    await waitFor(() => calls.some((call) => call.url.endsWith('/payments')));
    const payment = calls.filter((call) => call.url.endsWith('/payments')).at(-1);
    expect(payment?.body).toMatchObject({
      recipientId: 'northline-studio',
      amountMinor: 1250,
      method: 'card',
      note: 'Studio invoice',
      quoteId: 'quote-fresh',
    });
    expect(payment?.key).toBeTruthy();
  });
});
