import { describe, expect, it } from 'vitest';
import { baselinePaymentChoices } from './paymentChoices';

describe('baseline payment choices', () => {
  it('defaults to Adyen card and Worldpay bank', () => {
    expect(baselinePaymentChoices()).toEqual([
      { id: 'adyen', method: 'card', name: 'Adyen', label: 'Debit card · Adyen' },
      { id: 'worldpay', method: 'bank', name: 'Worldpay', label: 'Bank payment · Worldpay' },
    ]);
  });

  it('uses catalog names only for the matching baseline method', () => {
    const choices = baselinePaymentChoices([
      { id: 'adyen', name: ' Adyen ', methods: ['card'] },
      { id: 'worldpay', name: 'Worldpay', methods: ['bank'] },
    ]);
    expect(choices.map((choice) => choice.name)).toEqual(['Adyen', 'Worldpay']);
  });

  it('ignores an unlisted catalog provider and crossed methods', () => {
    const choices = baselinePaymentChoices([
      { id: 'other', name: 'Other', methods: ['card', 'bank'] },
      { id: 'adyen', name: 'Renamed Card', methods: ['bank'] },
      { id: 'worldpay', name: 'Renamed Bank', methods: ['card'] },
    ]);
    expect(choices.map((choice) => choice.id)).toEqual(['adyen', 'worldpay']);
    expect(choices.map((choice) => choice.method)).toEqual(['card', 'bank']);
    expect(choices.map((choice) => choice.name)).toEqual(['Adyen', 'Worldpay']);
    expect(JSON.stringify(choices)).not.toContain('Other');
  });
});
