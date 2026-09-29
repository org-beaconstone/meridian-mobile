export type BaselineId = 'adyen' | 'worldpay';
export type PaymentMethodName = 'card' | 'bank';

export type CatalogProvider = {
  id: string;
  name: string;
  description?: string;
  methods: string[];
  available?: boolean;
};

export type CatalogCorridor = {
  id?: string;
  provider: string;
  method: string;
  currency?: string;
  available?: boolean;
};

export type CatalogPayload = {
  demoDate?: string;
  recipients: Array<{
    id: string;
    name: string;
    category: 'Shopping' | 'Food & drink' | 'Transport' | 'Bills' | 'Lifestyle';
    initials: string;
    detail: string;
  }>;
  providers?: CatalogProvider[];
  corridors?: CatalogCorridor[];
};

export const CATALOG_TTL_MS = 300_000;

export type CatalogOrigin = 'network' | 'cache' | 'fallback' | 'baseline';

export type StoredCatalog = {
  fetchedAtEpochMillis: number;
  catalog: CatalogPayload;
};

export type CatalogChoice = {
  id: BaselineId;
  method: PaymentMethodName;
  title: string;
  name: string;
};

const CHOICES: Record<BaselineId, CatalogChoice> = {
  adyen: { id: 'adyen', method: 'card', title: 'Debit card', name: 'Adyen' },
  worldpay: { id: 'worldpay', method: 'bank', title: 'Bank payment', name: 'Worldpay' },
};

export function baselineCatalog(): CatalogPayload {
  return {
    demoDate: '',
    recipients: [],
    providers: [
      {
        id: 'adyen',
        name: 'Adyen',
        description: 'Card payment processor',
        methods: ['card'],
        available: true,
      },
      {
        id: 'worldpay',
        name: 'Worldpay',
        description: 'Bank payment processor',
        methods: ['bank'],
        available: true,
      },
    ],
    corridors: [
      { id: 'gb-card', provider: 'adyen', method: 'card', currency: 'GBP', available: true },
      { id: 'gb-bank', provider: 'worldpay', method: 'bank', currency: 'GBP', available: true },
    ],
  };
}

export function matchesBaseline(provider: CatalogProvider): provider is CatalogProvider & { id: BaselineId } {
  if (provider.id === 'adyen') return provider.methods.length === 1 && provider.methods[0] === 'card';
  if (provider.id === 'worldpay') return provider.methods.length === 1 && provider.methods[0] === 'bank';
  return false;
}

/** Returns the payload when every provider and corridor stays on the Adyen/Worldpay GBP baseline. */
export function acceptCatalog(catalog: CatalogPayload | null | undefined): CatalogPayload | null {
  if (!catalog || !Array.isArray(catalog.providers) || catalog.providers.length === 0) return null;
  const ids = catalog.providers.map((provider) => provider.id);
  if (new Set(ids).size !== ids.length) return null;
  if (!catalog.providers.every((provider) => matchesBaseline(provider))) return null;
  for (const corridor of catalog.corridors ?? []) {
    if ((corridor.currency ?? 'GBP') !== 'GBP') return null;
    const paired =
      (corridor.provider === 'adyen' && corridor.method === 'card') ||
      (corridor.provider === 'worldpay' && corridor.method === 'bank');
    if (!paired) return null;
  }
  return catalog;
}

export function activeChoices(catalog: CatalogPayload): CatalogChoice[] {
  const choices: CatalogChoice[] = [];
  for (const provider of catalog.providers ?? []) {
    if (provider.available === false || !matchesBaseline(provider)) continue;
    choices.push(CHOICES[provider.id]);
  }
  return choices;
}

export function cacheIsFresh(cached: StoredCatalog | null, now: number, ttlMs: number): boolean {
  return cached !== null && now >= cached.fetchedAtEpochMillis && now - cached.fetchedAtEpochMillis < ttlMs;
}

export type RefreshOutcome =
  | { type: 'success'; catalog: CatalogPayload }
  | { type: 'unrecognized' }
  | { type: 'gateway' }
  | { type: 'offline' }
  | { type: 'other' };

export function isGatewayStatus(status: number): boolean {
  return status === 500 || status === 502 || status === 503 || status === 504;
}

export function resolveCatalog(input: {
  cached: StoredCatalog | null;
  now: number;
  outcome: RefreshOutcome;
}): { catalog: CatalogPayload; origin: CatalogOrigin; persist: StoredCatalog | null } {
  const { cached, now, outcome } = input;
  if (outcome.type === 'success') {
    const accepted = acceptCatalog(outcome.catalog);
    if (accepted) {
      return {
        catalog: accepted,
        origin: 'network',
        persist: { fetchedAtEpochMillis: now, catalog: accepted },
      };
    }
  }
  if (cached) return { catalog: cached.catalog, origin: 'fallback', persist: null };
  return { catalog: baselineCatalog(), origin: 'baseline', persist: null };
}
