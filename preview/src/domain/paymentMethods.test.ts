import { describe, expect, it } from 'vitest';
import {
  paymentMethodBlockMessage,
  paymentMethodSheetModel,
  paymentMethodUnavailableText,
  submittablePaymentMethod,
} from './paymentMethods';

const catalog = [
  { id: 'worldpay', name: 'Worldpay', description: 'Bank transfer processor', methods: ['bank'] },
  { id: 'adyen', name: 'Adyen', description: 'Card payment processor', methods: ['card'] },
  { id: 'adyen', name: 'Adyen', description: 'Card payment processor', methods: ['card'] },
];

describe('payment method sheet', () => {
  it('follows catalog order for the GBP corridor', () => {
    const model = paymentMethodSheetModel(catalog);
    expect(model.loading).toBe(false);
    expect(model.options.map((option) => option.title)).toEqual(['Worldpay', 'Adyen Card']);
    expect(model.options[0].accessibilityLabel).toBe('Select Worldpay, radio button, 1 of 2');
    expect(model.options[1].accessibilityLabel).toBe('Select Adyen Card, radio button, 2 of 2');
    expect(model.options.every((option) => option.selectable && option.helperText === null)).toBe(
      true,
    );
    expect(submittablePaymentMethod('bank', model)).toBe('bank');
  });

  it('keeps an unavailable method disabled instead of switching provider', () => {
    const model = paymentMethodSheetModel([
      { id: 'adyen', name: 'Adyen', methods: ['card'], availability: 'unavailable' },
      { id: 'worldpay', name: 'Worldpay', methods: ['bank'], availability: 'degraded' },
    ]);
    expect(model.options.every((option) => option.helperText === paymentMethodUnavailableText)).toBe(
      true,
    );
    expect(submittablePaymentMethod('card', model)).toBeNull();
    expect(paymentMethodBlockMessage('card', model)).toBe(paymentMethodUnavailableText);
  });

  it('disables contracted methods outside the GBP corridor', () => {
    const model = paymentMethodSheetModel(
      [{ id: 'adyen', name: 'Adyen', methods: ['card'] }],
      { region: 'FR', currency: 'EUR' },
    );
    expect(model.options).toHaveLength(1);
    expect(model.options[0].selectable).toBe(false);
    expect(model.options[0].helperText).toBe(paymentMethodUnavailableText);
  });

  it('shows two placeholders while the catalog is unresolved and omits unknown entries', () => {
    const loading = paymentMethodSheetModel(null);
    expect(loading).toMatchObject({ loading: true, placeholderCount: 2, options: [] });
    expect(paymentMethodBlockMessage('card', loading)).toBe('Payment methods are still loading.');
    const model = paymentMethodSheetModel([
      { id: 'adyen', name: 'Adyen', methods: ['card', 'other'] },
      { id: 'unlisted', name: 'Unlisted', methods: ['card'] },
      {
        id: 'worldpay',
        name: 'Worldpay',
        methods: ['bank'],
        availability: 'unavailable',
      },
    ]);
    expect(model.options.map((option) => [option.title, option.selectable])).toEqual([
      ['Adyen Card', true],
      ['Worldpay', false],
    ]);
  });
});
