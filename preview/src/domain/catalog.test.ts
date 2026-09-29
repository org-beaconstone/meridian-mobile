import { describe, expect, it } from 'vitest';
import { readCatalogCache, writeCatalogCache } from './catalogStorage';
import {
  acceptCatalog,
  activeChoices,
  baselineCatalog,
  cacheIsFresh,
  isGatewayStatus,
  resolveCatalog,
  type CatalogPayload,
} from './catalog';

const adyen = {
  id: 'adyen',
  name: 'Adyen',
  description: 'Card payment processor',
  methods: ['card'],
};
const worldpay = {
  id: 'worldpay',
  name: 'Worldpay',
  description: 'Bank payment processor',
  methods: ['bank'],
};

function payload(providers: CatalogPayload['providers'], corridors?: CatalogPayload['corridors']): CatalogPayload {
  return {
    demoDate: '2026-09-18',
    recipients: [
      {
        id: 'northline-studio',
        name: 'Northline Studio',
        initials: 'NS',
        detail: 'Design',
        category: 'Shopping',
      },
    ],
    providers,
    corridors,
  };
}

describe('catalog baseline', () => {
  it('keeps a legacy payload available and hides an unavailable baseline method', () => {
    const legacy = payload([adyen, worldpay]);
    expect(acceptCatalog(legacy)).toEqual(legacy);
    expect(activeChoices(legacy).map((choice) => choice.id)).toEqual(['adyen', 'worldpay']);
    const hidden = payload([{ ...adyen, available: false }, worldpay]);
    expect(activeChoices(hidden).map((choice) => choice.method)).toEqual(['bank']);
  });

  it('rejects an unrecognized provider instead of presenting it', () => {
    const foreign = payload([
      adyen,
      { id: 'unrecognized', name: 'X', description: 'Y', methods: ['card'] },
    ]);
    expect(acceptCatalog(foreign)).toBeNull();
    expect(activeChoices(foreign).every((choice) => choice.id === 'adyen' || choice.id === 'worldpay')).toBe(
      true,
    );
  });

  it('rejects a swapped Adyen method and a non-GBP corridor', () => {
    expect(acceptCatalog(payload([{ ...adyen, methods: ['bank'] }]))).toBeNull();
    expect(
      acceptCatalog(payload([adyen, worldpay], [{ provider: 'adyen', method: 'card', currency: 'EUR' }])),
    ).toBeNull();
    expect(activeChoices(baselineCatalog()).map((choice) => choice.name)).toEqual(['Adyen', 'Worldpay']);
  });

  it('reuses the saved catalog after gateway, offline, and unrecognized refreshes', () => {
    const saved = {
      fetchedAtEpochMillis: 1_000,
      catalog: payload([adyen, worldpay]),
    };
    expect(cacheIsFresh(saved, 1_100, 300)).toBe(true);
    expect(cacheIsFresh(saved, 1_400, 300)).toBe(false);
    for (const outcome of [
      { type: 'gateway' } as const,
      { type: 'offline' } as const,
      { type: 'unrecognized' } as const,
    ]) {
      const resolved = resolveCatalog({ cached: saved, now: 2_000, outcome });
      expect(resolved.origin).toBe('fallback');
      expect(resolved.persist).toBeNull();
      expect(resolved.catalog.providers?.map((provider) => provider.id)).toEqual(['adyen', 'worldpay']);
    }
    const stored = resolveCatalog({
      cached: saved,
      now: 2_000,
      outcome: { type: 'success', catalog: payload([{ ...adyen, available: false }, worldpay]) },
    });
    expect(stored.origin).toBe('network');
    expect(activeChoices(stored.catalog).map((choice) => choice.id)).toEqual(['worldpay']);
    const empty = resolveCatalog({ cached: null, now: 2_000, outcome: { type: 'offline' } });
    expect(empty.origin).toBe('baseline');
    expect(empty.catalog.providers?.map((provider) => provider.id)).toEqual(['adyen', 'worldpay']);
    expect(isGatewayStatus(500) && isGatewayStatus(502) && isGatewayStatus(504)).toBe(true);
    expect(isGatewayStatus(404)).toBe(false);
  });

  it('stores the catalog as ciphertext in session storage', async () => {
    sessionStorage.clear();
    const catalog = payload([adyen, worldpay]);
    catalog.recipients[0].name = 'CACHE-TOKEN-XYZZY';
    await writeCatalogCache('room-a', { fetchedAtEpochMillis: 42, catalog });
    const blob = sessionStorage.getItem('meridian.catalog.room-a.blob') ?? '';
    expect(blob.includes('CACHE-TOKEN-XYZZY')).toBe(false);
    const restored = await readCatalogCache('room-a');
    expect(restored?.fetchedAtEpochMillis).toBe(42);
    expect(restored?.catalog.recipients[0].name).toBe('CACHE-TOKEN-XYZZY');
    expect(await readCatalogCache('room-b')).toBeNull();
  });
});
