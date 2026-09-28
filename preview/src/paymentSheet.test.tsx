import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
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
      detail: 'Design tools',
      category: 'Shopping',
      color: '#FF6B6B',
    },
  ],
  providers: [
    {
      id: 'adyen',
      name: 'Adyen',
      description: 'Card payment processor',
      methods: ['card'],
      status: 'available',
    },
    {
      id: 'worldpay',
      name: 'Worldpay',
      description: 'Bank payment processor',
      methods: ['bank'],
      status: 'unavailable',
    },
    {
      id: 'not-baseline',
      name: 'Not Shown',
      description: 'Ignored',
      methods: ['card'],
      status: 'available',
    },
  ],
};

function jsonResponse(body: unknown) {
  return {
    ok: true,
    status: 200,
    json: async () => body,
  };
}

describe('browser companion payment sheet', () => {
  let root: Root;
  let container: HTMLDivElement;
  let releaseCatalog: () => void;

  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
    let resolveCatalog: () => void = () => {};
    const catalogReady = new Promise<void>((resolve) => {
      resolveCatalog = resolve;
    });
    releaseCatalog = resolveCatalog;
    vi.stubGlobal('fetch', async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.endsWith('/state')) return jsonResponse(state);
      if (url.endsWith('/catalog')) {
        await catalogReady;
        return jsonResponse(catalog);
      }
      throw new Error(`unexpected ${url}`);
    });
  });

  afterEach(async () => {
    releaseCatalog();
    await act(async () => {
      root.unmount();
    });
    container.remove();
    vi.unstubAllGlobals();
  });

  it('shows skeletons, then a bottom sheet whose unavailable rail cannot be selected', async () => {
    await act(async () => {
      root.render(<App />);
    });
    await waitFor(() => document.body.textContent?.includes('Connected API') ?? false);

    await clickButton('Pay');
    await waitFor(() => document.querySelector('[aria-label="Loading payment methods"]') !== null);

    await act(async () => {
      releaseCatalog();
    });
    await waitFor(
      () => document.body.textContent?.includes('Adyen card (UK debit, usually instant)') ?? false,
    );
    expect(document.body.textContent).not.toContain('Not Shown');

    await clickButton('Payment method, Debit card');
    await waitFor(() => document.querySelector('[role="dialog"]') !== null);
    const card = document.querySelector('[aria-label="Select Debit card, radio button, 1 of 2"]');
    const bank = document.querySelector('[aria-label="Select Bank payment, radio button, 2 of 2"]');
    expect(card).not.toBeNull();
    expect(bank).not.toBeNull();
    expect(card?.getAttribute('aria-checked')).toBe('true');
    expect(document.body.textContent).toContain(
      'This payment method is temporarily unavailable in your region.',
    );

    await clickButton('Select Bank payment, radio button, 2 of 2');
    expect(card?.getAttribute('aria-checked')).toBe('true');
    expect(document.querySelector('[role="dialog"]')).not.toBeNull();

    await clickButton('Close payment methods');
    await waitFor(() => document.querySelector('[role="dialog"]') === null);
  });
});

async function waitFor(predicate: () => boolean) {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    if (predicate()) return;
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 25));
    });
  }
  throw new Error(document.body.textContent ?? 'timed out');
}

async function clickButton(name: string) {
  const button = [...document.querySelectorAll('button')].find(
    (candidate) => candidate.textContent === name || candidate.getAttribute('aria-label') === name,
  );
  if (!button) throw new Error(`missing button ${name}`);
  await act(async () => {
    button.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  });
}
