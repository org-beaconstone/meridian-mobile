export const MOBILE_EU_PAYMENTS_FLAG = 'enable_mobile_eu_payments';

export type CurrencyCode = 'GBP' | 'EUR';
export type RailMethod = 'card' | 'bank';
export type RailProvider = 'adyen' | 'worldpay';

export interface PaymentRail {
  id: string;
  provider: RailProvider;
  method: RailMethod;
  currency: CurrencyCode;
  label: string;
}

export interface CatalogProvider {
  id?: string;
  name?: string;
  methods?: readonly string[];
  currencies?: readonly string[];
  regions?: readonly string[];
}

export interface PaymentSurface {
  flagEnabled: boolean;
  dynamicCatalogActive: boolean;
  usingCachedGbp: boolean;
  currencies: CurrencyCode[];
  rails: PaymentRail[];
}

export interface PaymentSelection {
  currency: CurrencyCode;
  railId: string;
  reviewing: boolean;
}

export const GBP_BASELINE: PaymentRail[] = [
  {
    id: 'adyen-card-gbp',
    provider: 'adyen',
    method: 'card',
    currency: 'GBP',
    label: 'Debit card · Adyen',
  },
  {
    id: 'worldpay-bank-gbp',
    provider: 'worldpay',
    method: 'bank',
    currency: 'GBP',
    label: 'Bank payment · Worldpay',
  },
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function coerceFlag(value: unknown): boolean {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') return value.toLowerCase() === 'true';
  return false;
}

/** Boolean true or the string "true" enables the flag. Every other payload disables it. */
export function evaluateMobileEuPaymentsFlag(payload: unknown): boolean {
  if (!isRecord(payload)) return false;
  if (MOBILE_EU_PAYMENTS_FLAG in payload && payload[MOBILE_EU_PAYMENTS_FLAG] != null) {
    return coerceFlag(payload[MOBILE_EU_PAYMENTS_FLAG]);
  }
  const flags = payload.flags;
  if (isRecord(flags) && MOBILE_EU_PAYMENTS_FLAG in flags) {
    return coerceFlag(flags[MOBILE_EU_PAYMENTS_FLAG]);
  }
  return false;
}

/**
 * Flag off keeps the cached GBP Adyen/Worldpay list and hides EUR.
 * Flag on may relabel those two rails from the catalog and add EUR.
 * The rail list is never empty, and no other provider is shown.
 */
export function resolvePaymentSurface(
  flagEnabled: boolean,
  providers: readonly CatalogProvider[] | null | undefined,
  cachedGbp: readonly PaymentRail[],
): { surface: PaymentSurface; cachedGbp: PaymentRail[] } {
  const cached = sanitizeGbp(cachedGbp);
  if (!flagEnabled) {
    return {
      surface: {
        flagEnabled: false,
        dynamicCatalogActive: false,
        usingCachedGbp: true,
        currencies: ['GBP'],
        rails: cached,
      },
      cachedGbp: cached,
    };
  }

  const gbp = [...cached];
  let eur: PaymentRail[] = [];
  let recognized = 0;
  let relabelled = false;
  const seen = new Set<RailProvider>();

  for (const provider of providers ?? []) {
    const pair = recognizedPair(provider);
    if (!pair || seen.has(pair.provider)) continue;
    seen.add(pair.provider);
    recognized += 1;
    const name = displayName(provider, pair.provider);
    if (offers(provider, 'GBP')) {
      gbp[pair.index] = {
        id: pair.gbpId,
        provider: pair.provider,
        method: pair.method,
        currency: 'GBP',
        label: gbpLabel(name, pair.method),
      };
      relabelled = true;
    }
    if (offers(provider, 'EUR')) {
      eur.push({
        id: pair.eurId,
        provider: pair.provider,
        method: pair.method,
        currency: 'EUR',
        label: eurLabel(name, pair.method),
      });
    }
  }

  if (recognized === 0) eur = cached.map(eurVersion);

  return {
    surface: {
      flagEnabled: true,
      dynamicCatalogActive: recognized > 0,
      usingCachedGbp: !relabelled,
      currencies: eur.length === 0 ? ['GBP'] : ['GBP', 'EUR'],
      rails: [...gbp, ...eur],
    },
    cachedGbp: gbp,
  };
}

export function reconcileSelection(
  surface: PaymentSurface,
  currency: CurrencyCode,
  railId: string,
  reviewing: boolean,
): PaymentSelection {
  const rails = surface.rails.length > 0 ? surface.rails : GBP_BASELINE;
  const allowed: CurrencyCode = surface.currencies.includes(currency) ? currency : 'GBP';
  const pool = rails.filter((rail) => rail.currency === allowed);
  const choices = pool.length > 0 ? pool : rails;
  const kept = choices.find((rail) => rail.id === railId);
  const chosen = kept ?? choices[0];
  return {
    currency: allowed,
    railId: chosen.id,
    reviewing: reviewing && kept !== undefined && allowed === currency,
  };
}

function recognizedPair(
  provider: CatalogProvider,
): { provider: RailProvider; method: RailMethod; index: number; gbpId: string; eurId: string } | null {
  const id = provider.id?.toLowerCase();
  const methods = (provider.methods ?? []).map((method) => method.toLowerCase());
  if (id === 'adyen' && methods.includes('card')) {
    return { provider: 'adyen', method: 'card', index: 0, gbpId: 'adyen-card-gbp', eurId: 'adyen-card-eur' };
  }
  if (id === 'worldpay' && methods.includes('bank')) {
    return {
      provider: 'worldpay',
      method: 'bank',
      index: 1,
      gbpId: 'worldpay-bank-gbp',
      eurId: 'worldpay-bank-eur',
    };
  }
  return null;
}

function sanitizeGbp(rails: readonly PaymentRail[]): PaymentRail[] {
  const adyen = rails.find((rail) => rail.provider === 'adyen' && rail.method === 'card' && rail.currency === 'GBP');
  const worldpay = rails.find(
    (rail) => rail.provider === 'worldpay' && rail.method === 'bank' && rail.currency === 'GBP',
  );
  return [adyen ?? GBP_BASELINE[0], worldpay ?? GBP_BASELINE[1]];
}

function displayName(provider: CatalogProvider, id: RailProvider): string {
  const name = provider.name?.trim();
  if (name) return name;
  return id === 'adyen' ? 'Adyen' : 'Worldpay';
}

function offers(provider: CatalogProvider, currency: 'GBP' | 'EUR'): boolean {
  const currencies = (provider.currencies ?? []).map((item) => item.toUpperCase());
  if (currencies.length > 0) return currencies.includes(currency);
  if (currency === 'GBP') return true;
  const regions = (provider.regions ?? []).map((item) => item.toUpperCase());
  if (regions.length > 0) return regions.some((item) => item === 'EU' || item === 'EEA' || item === 'EUR');
  return true;
}

function gbpLabel(name: string, method: RailMethod): string {
  return method === 'card' ? `Debit card · ${name}` : `Bank payment · ${name}`;
}

function eurLabel(name: string, method: RailMethod): string {
  return `${gbpLabel(name, method)} · EUR`;
}

function eurVersion(rail: PaymentRail): PaymentRail {
  const name = rail.provider === 'adyen' ? 'Adyen' : 'Worldpay';
  return {
    id: rail.provider === 'adyen' ? 'adyen-card-eur' : 'worldpay-bank-eur',
    provider: rail.provider,
    method: rail.method,
    currency: 'EUR',
    label: eurLabel(name, rail.method),
  };
}
