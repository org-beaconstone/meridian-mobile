import { describe, expect, it } from 'vitest';
import {
  REGION_UNAVAILABLE,
  railAnnouncement,
  readProviders,
  resolvePaymentRails,
} from './paymentRails';

const catalog = {
  providers: [
    { id: 'worldpay', name: 'Worldpay', description: 'Bank transfer processor', methods: ['bank'] },
    { id: 'adyen', name: 'Adyen', description: 'Card payment processor', methods: ['card'] },
    { id: 'other', name: 'Extra Rail', description: 'Should not render', methods: ['card'] },
  ],
};

describe('payment method sheet rails', () => {
  it('renders catalog badges for the baseline pair only', () => {
    const options = resolvePaymentRails(readProviders(catalog));
    expect(options.map((option) => option.method)).toEqual(['card', 'bank']);
    expect(options[0]?.badge).toBe('Debit card · Adyen (Card payment processor)');
    expect(options[1]?.badge).toBe('Bank payment · Worldpay (Bank transfer processor)');
    expect(options.every((option) => option.available)).toBe(true);
    expect(railAnnouncement(options[0], 1, options.length)).toBe(
      'Select Debit card, radio button, 1 of 2',
    );
    expect(railAnnouncement(options[1], 2, options.length)).toBe(
      'Select Bank payment, radio button, 2 of 2',
    );
    expect(JSON.stringify(options)).not.toContain('Extra');
  });

  it('disables a baseline rail missing from the catalog', () => {
    const options = resolvePaymentRails(
      readProviders({
        providers: [{ id: 'adyen', name: 'Adyen', description: 'Card payment processor', methods: ['card'] }],
      }),
    );
    const bank = options.find((option) => option.method === 'bank');
    expect(options).toHaveLength(2);
    expect(bank).toMatchObject({
      available: false,
      badge: 'Bank payment · Worldpay',
      warning: REGION_UNAVAILABLE,
    });
    expect(railAnnouncement(bank!, 2, options.length)).toBe(
      `Select Bank payment, radio button, 2 of 2. ${REGION_UNAVAILABLE}`,
    );
  });

  it('keeps a provider disabled when its method is absent', () => {
    const options = resolvePaymentRails(
      readProviders({
        providers: [
          { id: 'adyen', name: 'Adyen Cards', description: 'Card payment processor', methods: [] },
          { id: 'worldpay', name: 'Worldpay', description: 'Bank transfer processor', methods: ['bank', 'wallet'] },
        ],
      }),
    );
    const card = options.find((option) => option.method === 'card');
    expect(card?.available).toBe(false);
    expect(card?.badge).toBe('Debit card · Adyen Cards');
    expect(card?.badge).not.toContain('Card payment processor');
    expect(options.find((option) => option.method === 'bank')?.available).toBe(true);
    expect(JSON.stringify(options)).not.toContain('wallet');
  });

  it('omits an empty description', () => {
    const options = resolvePaymentRails(
      readProviders({ providers: [{ id: 'adyen', name: 'Adyen', description: '  ', methods: ['card'] }] }),
    );
    expect(options[0]?.badge).toBe('Debit card · Adyen');
  });
});
