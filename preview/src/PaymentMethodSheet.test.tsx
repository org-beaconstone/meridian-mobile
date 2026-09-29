import { act, type ReactNode } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, describe, expect, it } from 'vitest';
import PaymentMethodSheet from './PaymentMethodSheet';
import { REGION_UNAVAILABLE, readProviders, resolvePaymentRails } from './domain/paymentRails';

let root: Root | null = null;
let container: HTMLDivElement | null = null;

function render(node: ReactNode) {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() => {
    root?.render(node);
  });
}

afterEach(() => {
  act(() => root?.unmount());
  container?.remove();
  root = null;
  container = null;
});

describe('payment method bottom sheet', () => {
  it('shows animated skeleton cards while the catalog is unresolved', () => {
    render(
      <PaymentMethodSheet
        method="card"
        rails={null}
        onSelect={() => {}}
        onCommit={() => {}}
        onClose={() => {}}
      />,
    );
    expect(document.querySelector('[aria-label="Loading payment methods"]')).not.toBeNull();
    expect(document.querySelectorAll('.rail-skeleton')).toHaveLength(2);
    expect(document.querySelector('[role="radio"]')).toBeNull();
  });

  it('announces each catalog option and refuses an unavailable rail', () => {
    const rails = resolvePaymentRails(
      readProviders({
        providers: [
          { id: 'adyen', name: 'Adyen', description: 'Card payment processor', methods: ['card'] },
        ],
      }),
    );
    const committed: string[] = [];
    render(
      <PaymentMethodSheet
        method="card"
        rails={rails}
        onSelect={() => {}}
        onCommit={(method) => committed.push(method)}
        onClose={() => {}}
      />,
    );
    const options = [...document.querySelectorAll('[role="radio"]')];
    expect(options.map((option) => option.getAttribute('aria-label'))).toEqual([
      'Select Debit card, radio button, 1 of 2',
      `Select Bank payment, radio button, 2 of 2. ${REGION_UNAVAILABLE}`,
    ]);
    const bank = options[1] as HTMLButtonElement;
    expect(bank.getAttribute('aria-disabled')).toBe('true');
    expect(bank.textContent).toContain(REGION_UNAVAILABLE);
    act(() => {
      bank.click();
    });
    expect(committed).toEqual([]);
    act(() => {
      (options[0] as HTMLButtonElement).click();
    });
    expect(committed).toEqual(['card']);
  });
});
