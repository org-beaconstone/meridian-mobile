import { describe, expect, it } from 'vitest';
import {
  decodeCatalog,
  legacyFlag,
  parseFeatureFlag,
  paymentMethodChoices,
  paymentTelemetryEvent,
  readFlagCache,
  writeFlagCache,
} from './featureFlags';

const recipient = {
  id: 'northline-studio',
  name: 'Northline Studio',
  initials: 'NS',
  detail: 'Design tools',
  category: 'Shopping',
  color: '#112233',
};

describe('dual-model catalog', () => {
  it('parses the legacy two-provider document', () => {
    const catalog = decodeCatalog({
      demoDate: '2026-09-18',
      recipients: [recipient],
      providers: [
        { id: 'adyen', name: 'Adyen', description: 'Card processor', methods: ['card'] },
        { id: 'worldpay', name: 'Worldpay', description: 'Bank payment', methods: ['bank'] },
      ],
    });
    expect(catalog?.schema).toBe('legacy');
    expect(catalog?.providers.map((provider) => provider.id)).toEqual(['adyen', 'worldpay']);
    expect(catalog?.currencies).toEqual(['GBP']);
  });

  it('parses a dynamic catalog and drops unknown providers and currencies', () => {
    const catalog = decodeCatalog({
      schema: 'dynamic',
      demoDate: '2026-09-18',
      recipients: [recipient],
      currencies: [{ code: 'EUR' }, { code: 'USD' }, 'GBP'],
      methods: [
        { providerId: 'adyen', label: 'Adyen', method: 'card' },
        { providerId: 'worldpay', name: 'Worldpay', rail: 'bank' },
        { providerId: 'extra', name: 'Extra rail', method: 'card' },
      ],
    });
    expect(catalog?.schema).toBe('dynamic');
    expect(catalog?.providers).toEqual([
      { id: 'adyen', name: 'Adyen', method: 'card' },
      { id: 'worldpay', name: 'Worldpay', method: 'bank' },
    ]);
    expect(catalog?.currencies).toEqual(['EUR', 'GBP']);
  });

  it('returns null for a non-object payload instead of throwing', () => {
    expect(decodeCatalog('nope')).toBeNull();
    expect(decodeCatalog(null)).toBeNull();
  });
});

describe('enable_mobile_eu_payments', () => {
  it('treats a missing flag and an explicit kill switch as legacy', () => {
    expect(parseFeatureFlag({})).toEqual({ enabled: false, variant: 'legacy' });
    expect(parseFeatureFlag({ flags: { enable_mobile_eu_payments: { enabled: true, killSwitch: true } } })).toEqual({
      enabled: false,
      variant: 'legacy',
    });
    expect(parseFeatureFlag({ enable_mobile_eu_payments: false })).toEqual({ enabled: false, variant: 'legacy' });
  });

  it('reads an enabled dynamic variant from the common envelopes', () => {
    expect(parseFeatureFlag({ enable_mobile_eu_payments: { enabled: true, variant: 'dynamic' } })).toEqual({
      enabled: true,
      variant: 'dynamic',
    });
    expect(
      parseFeatureFlag({
        flags: [{ key: 'enable_mobile_eu_payments', enabled: true, variant: 'eu_rehearsal' }],
      }),
    ).toEqual({ enabled: true, variant: 'eu_rehearsal' });
  });

  it('caches the evaluation per rehearsal room', () => {
    const storage = new Map<string, string>();
    const memory = {
      getItem: (key: string) => storage.get(key) ?? null,
      setItem: (key: string, value: string) => {
        storage.set(key, value);
      },
      removeItem: (key: string) => {
        storage.delete(key);
      },
      clear: () => storage.clear(),
      key: (index: number) => Array.from(storage.keys())[index] ?? null,
      get length() {
        return storage.size;
      },
    } satisfies Storage;
    writeFlagCache(memory, 'room-a', { key: 'enable_mobile_eu_payments', enabled: true, variant: 'dynamic', source: 'remote' });
    expect(readFlagCache(memory, 'room-a')?.variant).toBe('dynamic');
    expect(readFlagCache(memory, 'room-b')).toBeNull();
    expect(legacyFlag('default').enabled).toBe(false);
  });

  it('keeps the hardcoded methods until the flag is on', () => {
    const catalog = decodeCatalog({
      schema: 'dynamic',
      methods: [{ providerId: 'worldpay', name: 'Worldpay', method: 'bank' }],
    });
    expect(paymentMethodChoices(legacyFlag('remote'), catalog).map((provider) => provider.id)).toEqual(['adyen', 'worldpay']);
    expect(paymentMethodChoices({ key: 'enable_mobile_eu_payments', enabled: true, variant: 'dynamic', source: 'remote' }, catalog).map((provider) => provider.id)).toEqual(['worldpay']);
  });

  it('tags payment telemetry with the active variant', () => {
    const off = paymentTelemetryEvent(legacyFlag('cache'), 'key-1', 'EUR');
    expect(off).toMatchObject({ variant: 'legacy', currency: 'GBP', header: 'enable_mobile_eu_payments=legacy' });
    const on = paymentTelemetryEvent({ enabled: true, variant: 'dynamic' }, 'key-1', 'EUR');
    expect(on).toMatchObject({ variant: 'dynamic', currency: 'EUR', header: 'enable_mobile_eu_payments=dynamic' });
  });
});
