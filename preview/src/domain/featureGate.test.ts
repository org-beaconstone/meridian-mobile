import { describe, expect, it } from 'vitest';
import {
  evaluateMobileEuPaymentsFlag,
  GBP_BASELINE,
  reconcileSelection,
  resolvePaymentSurface,
} from './featureGate';

describe('enable_mobile_eu_payments', () => {
  it('keeps cached GBP rails and hides EUR when the flag is off', () => {
    const cached = [
      { ...GBP_BASELINE[0], label: 'Debit card · Adyen Cards' },
      GBP_BASELINE[1],
    ];
    const resolved = resolvePaymentSurface(
      false,
      [{ id: 'adyen', name: 'Adyen EU', methods: ['card'], currencies: ['GBP', 'EUR'] }],
      cached,
    );
    expect(resolved.surface.flagEnabled).toBe(false);
    expect(resolved.surface.dynamicCatalogActive).toBe(false);
    expect(resolved.surface.usingCachedGbp).toBe(true);
    expect(resolved.surface.currencies).toEqual(['GBP']);
    expect(resolved.surface.rails.map((rail) => rail.currency)).toEqual(['GBP', 'GBP']);
    expect(resolved.surface.rails.map((rail) => rail.label)).toEqual([
      'Debit card · Adyen Cards',
      'Bank payment · Worldpay',
    ]);
    expect(resolved.cachedGbp).toEqual(cached);
  });

  it('parses the catalog and unlocks EUR when the flag is on', () => {
    const resolved = resolvePaymentSurface(
      true,
      [
        { id: 'adyen', name: 'Adyen', methods: ['card'], currencies: ['GBP', 'EUR'] },
        { id: 'worldpay', name: 'Worldpay', methods: ['bank'], currencies: ['GBP', 'EUR'], regions: ['EU'] },
      ],
      GBP_BASELINE,
    );
    expect(resolved.surface.dynamicCatalogActive).toBe(true);
    expect(resolved.surface.usingCachedGbp).toBe(false);
    expect(resolved.surface.currencies).toEqual(['GBP', 'EUR']);
    expect(resolved.surface.rails.map((rail) => rail.id)).toEqual([
      'adyen-card-gbp',
      'worldpay-bank-gbp',
      'adyen-card-eur',
      'worldpay-bank-eur',
    ]);
    expect(new Set(resolved.surface.rails.map((rail) => rail.provider))).toEqual(new Set(['adyen', 'worldpay']));
  });

  it('lets an explicit GBP catalog withhold EUR', () => {
    const resolved = resolvePaymentSurface(
      true,
      [
        { id: 'adyen', name: 'Adyen', methods: ['card'], currencies: ['GBP'] },
        { id: 'worldpay', name: 'Worldpay', methods: ['bank'], currencies: ['GBP'] },
      ],
      GBP_BASELINE,
    );
    expect(resolved.surface.dynamicCatalogActive).toBe(true);
    expect(resolved.surface.rails.every((rail) => rail.currency === 'GBP')).toBe(true);
  });

  it('drops an unknown provider and keeps a non-empty GBP list', () => {
    const resolved = resolvePaymentSurface(
      true,
      [
        { id: 'pilot-rail', name: 'Pilot Rail', methods: ['card'], currencies: ['EUR'] },
        { id: 'adyen', name: 'Adyen', methods: ['bank'] },
        { id: 'worldpay', name: 'Worldpay', methods: ['bank'], regions: ['EU'] },
      ],
      GBP_BASELINE,
    );
    const labels = resolved.surface.rails.map((rail) => rail.label).join(' ');
    expect(labels).not.toContain('Pilot');
    expect(resolved.surface.rails[0]).toMatchObject({ provider: 'adyen', method: 'card', currency: 'GBP' });
    expect(resolved.surface.rails.some((rail) => rail.id === 'worldpay-bank-eur')).toBe(true);
    expect(resolved.surface.rails.length).toBeGreaterThan(0);
  });

  it('unlocks EUR from the baseline when the catalog is missing', () => {
    const resolved = resolvePaymentSurface(true, null, []);
    expect(resolved.surface.dynamicCatalogActive).toBe(false);
    expect(resolved.surface.usingCachedGbp).toBe(true);
    expect(resolved.surface.rails).toHaveLength(4);
    expect(resolved.cachedGbp).toEqual(GBP_BASELINE);
  });

  it('reverts an in-review EUR selection when the flag turns off', () => {
    const enabled = resolvePaymentSurface(true, null, GBP_BASELINE);
    const reviewing = reconcileSelection(enabled.surface, 'EUR', 'adyen-card-eur', true);
    expect(reviewing).toEqual({ currency: 'EUR', railId: 'adyen-card-eur', reviewing: true });
    const disabled = resolvePaymentSurface(false, null, enabled.cachedGbp);
    const settled = reconcileSelection(disabled.surface, reviewing.currency, reviewing.railId, reviewing.reviewing);
    expect(disabled.surface.rails.every((rail) => rail.currency === 'GBP')).toBe(true);
    expect(disabled.surface.rails).toHaveLength(2);
    expect(settled).toEqual({ currency: 'GBP', railId: 'adyen-card-gbp', reviewing: false });
  });

  it('keeps a GBP review on the same rail', () => {
    const surface = resolvePaymentSurface(false, null, GBP_BASELINE).surface;
    expect(reconcileSelection(surface, 'GBP', 'worldpay-bank-gbp', true)).toEqual({
      currency: 'GBP',
      railId: 'worldpay-bank-gbp',
      reviewing: true,
    });
  });

  it.each([
    [{ enable_mobile_eu_payments: true }, true],
    [{ enable_mobile_eu_payments: false }, false],
    [{ flags: { enable_mobile_eu_payments: true } }, true],
    [{ enable_mobile_eu_payments: 'true' }, true],
    [{ enable_mobile_eu_payments: 'false' }, false],
    [{ enable_mobile_eu_payments: 1 }, false],
    [{}, false],
    [null, false],
    ['nope', false],
  ])('evaluates %j', (payload, expected) => {
    expect(evaluateMobileEuPaymentsFlag(payload)).toBe(expected);
  });
});
