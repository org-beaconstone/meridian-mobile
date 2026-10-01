import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, describe, expect, it, vi } from 'vitest';
import App from './App';

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
      initials: 'NS',
      detail: 'Design tools & materials',
      category: 'Shopping',
      color: '#FF6B6B',
    },
  ],
  providers: [],
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

async function tick() {
  await act(async () => {
    await new Promise((resolve) => setTimeout(resolve, 0));
  });
}

async function waitFor(predicate: () => boolean) {
  for (let i = 0; i < 30; i++) {
    if (predicate()) return;
    await tick();
  }
  throw new Error('timed out waiting for the rehearsal screen');
}

describe('browser companion payment review', () => {
  let root: Root | undefined;
  const container = document.createElement('div');
  document.body.appendChild(container);

  afterEach(() => {
    act(() => root?.unmount());
    container.replaceChildren();
    vi.unstubAllGlobals();
  });

  it('shows the locked review and submits one intent for rapid confirms', async () => {
    const posts: { url: string; body: string; headers: Headers }[] = [];
    let release: (response: Response) => void = () => {};
    const gate = new Promise<Response>((resolve) => {
      release = resolve;
    });
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
        const url = String(input);
        if (url.endsWith('/state')) return jsonResponse(state);
        if (url.endsWith('/catalog')) return jsonResponse(catalog);
        posts.push({ url, body: String(init?.body ?? ''), headers: new Headers(init?.headers) });
        return gate;
      }),
    );
    root = createRoot(container);
    await act(async () => {
      root?.render(<App />);
    });
    await waitFor(() => container.textContent?.includes('Connected API') === true);
    const pay = [...container.querySelectorAll('button')].find((button) => button.textContent === 'Pay');
    await act(async () => {
      pay?.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    });
    const amount = container.querySelector('#mobile-amount') as HTMLInputElement;
    const reference = container.querySelector('#mobile-note') as HTMLInputElement;
    await act(async () => {
      setNativeValue(amount, '25.99');
      setNativeValue(reference, 'INV-1042');
    });
    const review = [...container.querySelectorAll('button')].find(
      (button) => button.textContent === 'Review payment',
    );
    await act(async () => {
      review?.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    });
    expect(container.querySelector('[data-testid="review-recipient"]')?.textContent).toContain(
      'Northline Studio',
    );
    expect(container.querySelector('[data-testid="review-amount"]')?.textContent).toBe('£25.99');
    expect(container.querySelector('[data-testid="review-fees"]')?.textContent).toBe('£0.39');
    expect(container.querySelector('[data-testid="review-method"]')?.textContent).toBe('Debit card');
    expect(container.querySelector('[data-testid="review-bank"]')?.textContent).toBe('Adyen');
    expect(container.querySelector('[data-testid="review-quote-expiry"]')?.textContent).toMatch(
      /^\d{1,2} [A-Z][a-z]{2} \d{4}, \d{2}:\d{2} UTC$/,
    );
    expect(container.querySelector('[data-testid="review-consent"]')?.textContent).toMatch(
      /does not move real money/,
    );
    const confirm = container.querySelector('[data-testid="confirm-payment"]') as HTMLButtonElement;
    expect(confirm.disabled).toBe(true);
    const checkbox = container.querySelector('.consent-check input') as HTMLInputElement;
    await act(async () => {
      checkbox.click();
    });
    expect(confirm.disabled).toBe(false);
    await act(async () => {
      confirm.dispatchEvent(new MouseEvent('click', { bubbles: true }));
      confirm.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    });
    expect(posts).toHaveLength(1);
    expect(posts[0].url).toBe('/api/v2/payment-intents');
    expect(posts[0].headers.get('X-Rehearsal-Session')).toBe('meridian-rehearsal');
    expect(posts[0].headers.get('Idempotency-Key')).toMatch(/^[0-9a-f-]{36}$/i);
    expect(posts[0].headers.get('X-Payload-Hash')).toHaveLength(64);
    expect(posts[0].body).toContain('"amountMinor":2599');
    expect(posts[0].body).toContain('"provider":"adyen"');
    release(jsonResponse({ ok: true, status: 'succeeded', intentId: 'pi_browser' }));
    await waitFor(() => container.textContent?.includes('pi_browser') === true);
    expect(container.textContent).toMatch(/not submitted again/);
    const again = container.querySelector('[data-testid="confirm-payment"]');
    expect(again).toBeNull();
    expect(posts).toHaveLength(1);
  });
});

function setNativeValue(input: HTMLInputElement, value: string) {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
  setter?.call(input, value);
  input.dispatchEvent(new Event('input', { bubbles: true }));
}
