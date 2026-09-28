import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import App from './App';
import { isUuidV4 } from './domain/payment';

const ledger = {
  version: 1,
  balance: 1_248_050,
  transactions: [],
  budgets: [
    { category: 'Shopping', limit: 100_000 },
    { category: 'Food & drink', limit: 50_000 },
    { category: 'Transport', limit: 50_000 },
    { category: 'Bills', limit: 90_000 },
    { category: 'Lifestyle', limit: 30_000 },
  ],
};

const catalog = {
  demoDate: '2026-09-18',
  recipients: [
    {
      id: 'northline-studio',
      name: 'Northline Studio',
      category: 'Shopping',
      initials: 'NS',
      detail: 'Design tools',
    },
  ],
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function header(init: RequestInit | undefined, name: string) {
  const headers = new Headers(init?.headers);
  return headers.get(name);
}

function button(name: string) {
  const found = [...document.querySelectorAll('button')].find((item) => item.textContent?.includes(name));
  if (!found) throw new Error(`Missing button ${name}`);
  return found as HTMLButtonElement;
}

async function setControl(id: string, value: string) {
  const element = document.getElementById(id);
  if (!(element instanceof HTMLInputElement || element instanceof HTMLSelectElement)) {
    throw new Error(`Missing control ${id}`);
  }
  await act(async () => {
    const prototype =
      element instanceof HTMLSelectElement ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(prototype, 'value')?.set?.call(element, value);
    element.dispatchEvent(new Event(element instanceof HTMLSelectElement ? 'change' : 'input', { bubbles: true }));
  });
}

describe('browser companion payment review', () => {
  let root: Root;
  let container: HTMLDivElement;
  const calls: { url: string; init?: RequestInit }[] = [];
  let paymentAttempts = 0;
  let quoteBody: Record<string, unknown> = {
    quoteId: 'q-1',
    amountMinor: 1000,
    targetAmountMinor: 1170,
    rate: '1.1700',
    sourceCurrency: 'GBP',
    targetCurrency: 'EUR',
    expiresInSeconds: 60,
  };

  beforeEach(() => {
    (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
    calls.length = 0;
    paymentAttempts = 0;
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
        const url = String(input);
        calls.push({ url, init });
        if (url.endsWith('/state')) return json(ledger);
        if (url.endsWith('/catalog')) return json(catalog);
        if (url.endsWith('/fx/quote')) return json(quoteBody);
        if (url.endsWith('/payments')) {
          paymentAttempts += 1;
          if (paymentAttempts < 3 && init?.body && String(init.body).includes('"scenario":"success"') && quoteBody.quoteId === 'retry') {
            return new Response('bad gateway', { status: paymentAttempts === 1 ? 502 : 504 });
          }
          return json({
            ok: true,
            state: { ...ledger, balance: 1_247_050 },
            transaction: {
              id: 'txn-new',
              name: 'Northline Studio',
              amount: 1000,
              date: '2026-09-28',
              category: 'Shopping',
              status: 'completed',
              provider: 'adyen',
              reference: 'REF-1',
            },
          });
        }
        return new Response('missing', { status: 404 });
      }),
    );
  });

  afterEach(() => {
    act(() => root.unmount());
    container.remove();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  async function render() {
    await act(async () => {
      root.render(<App />);
    });
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 20));
    });
  }

  it('keeps a GBP card payment on one idempotency key', async () => {
    await render();
    expect(document.querySelector('[data-testid="mobile-balance"]')?.textContent).toContain('12,480.50');
    await act(async () => {
      button('Pay').click();
    });
    await setControl('mobile-amount', '10.00');
    await act(async () => {
      document.querySelector('form')?.requestSubmit();
    });
    await act(async () => {
      button('Confirm payment').click();
    });
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 30));
    });
    const payments = calls.filter((call) => call.url.endsWith('/payments'));
    expect(payments).toHaveLength(1);
    const key = header(payments[0].init, 'Idempotency-Key');
    expect(key && isUuidV4(key)).toBe(true);
    expect(header(payments[0].init, 'X-Rehearsal-Session')).toBe('meridian-rehearsal');
    expect(String(payments[0].init?.body)).toContain('"method":"card"');
    expect(calls.some((call) => call.url.endsWith('/fx/quote'))).toBe(false);
    expect(document.body.textContent).toContain('Demo payment complete');
  });

  it('shows a 60 second EUR lock and blocks confirmation after it expires', async () => {
    let now = 1_700_000_000_000;
    vi.spyOn(Date, 'now').mockImplementation(() => now);
    await render();
    await act(async () => {
      button('Pay').click();
    });
    await setControl('mobile-amount', '10.00');
    await setControl('mobile-currency', 'EUR');
    await setControl('mobile-iban', 'GB82 WEST 1234 5698 7654 32');
    await act(async () => {
      document.querySelector('form')?.requestSubmit();
    });
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 30));
    });
    expect(document.querySelector('[data-testid="quote-countdown"]')?.textContent).toContain('Rate locked for 60s');
    expect(document.querySelector('[data-testid="quote-countdown"]')?.textContent).toContain('€11.70');
    expect(button('Confirm payment').disabled).toBe(false);
    now += 60_000;
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 300));
    });
    expect(document.body.textContent).toContain('Refresh the conversion rate');
    expect(button('Confirm payment').disabled).toBe(true);
    const before = calls.filter((call) => call.url.endsWith('/payments')).length;
    await act(async () => {
      button('Confirm payment').click();
    });
    expect(calls.filter((call) => call.url.endsWith('/payments'))).toHaveLength(before);
    await act(async () => {
      button('Refresh conversion rate').click();
    });
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 30));
    });
    expect(calls.filter((call) => call.url.endsWith('/fx/quote'))).toHaveLength(2);
    expect(document.querySelector('[data-testid="quote-countdown"]')?.textContent).toContain('Rate locked for 60s');
    expect(button('Confirm payment').disabled).toBe(false);
  });

  it('rejects an invalid IBAN before calling the API', async () => {
    await render();
    await act(async () => {
      button('Pay').click();
    });
    await setControl('mobile-amount', '10.00');
    await act(async () => {
      const label = [...document.querySelectorAll('label')].find((item) => item.textContent?.includes('Bank payment'));
      const input = label?.querySelector('input');
      if (!(input instanceof HTMLInputElement)) throw new Error('Missing bank method');
      input.click();
    });
    await setControl('mobile-iban', 'GB82WEST12345698765433');
    await act(async () => {
      document.querySelector('form')?.requestSubmit();
    });
    expect(document.body.textContent).toContain('Enter a valid recipient IBAN');
    expect(document.getElementById('mobile-amount')).toBeTruthy();
    expect(calls.some((call) => call.url.endsWith('/payments') || call.url.endsWith('/fx/quote'))).toBe(false);
  });

  it('retries gateway timeouts without a new idempotency key or provider', async () => {
    quoteBody = { ...quoteBody, quoteId: 'retry' };
    await render();
    await act(async () => {
      button('Pay').click();
    });
    await setControl('mobile-amount', '10.00');
    await act(async () => {
      document.querySelector('form')?.requestSubmit();
    });
    await act(async () => {
      button('Confirm payment').click();
    });
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 900));
    });
    const payments = calls.filter((call) => call.url.endsWith('/payments'));
    expect(payments).toHaveLength(3);
    const keys = payments.map((call) => header(call.init, 'Idempotency-Key'));
    expect(new Set(keys).size).toBe(1);
    expect(keys[0] && isUuidV4(keys[0])).toBe(true);
    expect(payments.every((call) => String(call.init?.body).includes('"method":"card"'))).toBe(true);
    expect(payments.every((call) => header(call.init, 'X-Rehearsal-Session') === 'meridian-rehearsal')).toBe(true);
    expect(document.body.textContent).toContain('Demo payment complete');
  });
});
