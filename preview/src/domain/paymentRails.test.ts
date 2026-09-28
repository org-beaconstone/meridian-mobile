import { describe, expect, it } from 'vitest';
import {
  ADYEN_CARD_BADGE,
  REGIONAL_UNAVAILABILITY_WARNING,
  WORLDPAY_BANK_BADGE,
  resolvePaymentRails,
} from './paymentRails';

describe('browser companion payment rails', () => {
  it('resolves the baseline in catalog order with screen-reader indexes', () => {
    const rails = resolvePaymentRails([
      { id: 'worldpay', name: 'Worldpay', methods: ['bank'] },
      { id: 'adyen', name: 'Adyen', methods: ['card'] },
    ]);
    expect(rails.map((rail) => rail.announcement)).toEqual([
      'Select Bank payment, radio button, 1 of 2',
      'Select Debit card, radio button, 2 of 2',
    ]);
    expect(rails[0]?.badge).toBe(WORLDPAY_BANK_BADGE);
    expect(rails[1]?.badge).toBe(ADYEN_CARD_BADGE);
    expect(rails.every((rail) => rail.selectable)).toBe(true);
  });

  it('disables degraded and offline rails with the regional warning', () => {
    const rails = resolvePaymentRails([
      { id: 'adyen', name: 'Adyen', methods: ['card'], status: 'degraded' },
      { id: 'worldpay', name: 'Worldpay', methods: ['bank'], status: 'OFFLINE' },
    ]);
    expect(rails.map((rail) => rail.availability)).toEqual(['degraded', 'unavailable']);
    expect(
      rails.every((rail) => !rail.selectable && rail.warning === REGIONAL_UNAVAILABILITY_WARNING),
    ).toBe(true);
  });

  it('ignores unknown providers, wrong pairings, and duplicates', () => {
    const rails = resolvePaymentRails([
      { id: 'adyen', name: 'Adyen', methods: ['bank', 'card'] },
      { id: 'adyen', name: 'Adyen duplicate', methods: ['card'] },
      { id: 'not-baseline', name: 'Not Shown', methods: ['card'], status: 'available' },
      { id: 'worldpay', name: 'Worldpay', methods: ['card'] },
    ]);
    expect(rails).toHaveLength(1);
    expect(rails[0]?.announcement).toBe('Select Debit card, radio button, 1 of 1');
    expect(JSON.stringify(rails)).not.toContain('Not Shown');
    expect(resolvePaymentRails([])).toEqual([]);
  });
});
