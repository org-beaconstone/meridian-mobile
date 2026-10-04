export const EU_PAYMENTS_FLAG = 'enable_mobile_eu_payments';

export type FlagSource = 'remote' | 'cache' | 'default';

export type FeatureFlagEvaluation = {
  key: string;
  enabled: boolean;
  variant: string;
  source: FlagSource;
};

export type PaymentTelemetryEvent = {
  action: 'payment.submit';
  flagKey: string;
  variant: string;
  currency: 'GBP' | 'EUR';
  idempotencyKey: string;
  header: string;
};

export type CatalogProvider = {
  id: 'adyen' | 'worldpay';
  name: string;
  method: 'card' | 'bank';
};

export type DecodedCatalog = {
  schema: 'legacy' | 'dynamic';
  demoDate: string;
  recipients: { id: string; name: string; category: string; initials: string; detail: string }[];
  providers: CatalogProvider[];
  currencies: Array<'GBP' | 'EUR'>;
};

const LEGACY_PROVIDERS: CatalogProvider[] = [
  { id: 'adyen', name: 'Adyen', method: 'card' },
  { id: 'worldpay', name: 'Worldpay', method: 'bank' },
];

export function legacyFlag(source: FlagSource): FeatureFlagEvaluation {
  return { key: EU_PAYMENTS_FLAG, enabled: false, variant: 'legacy', source };
}

export function cacheKey(sessionId: string) {
  return `${EU_PAYMENTS_FLAG}:${sessionId}`;
}

function sanitizeVariant(variant: unknown): string | null {
  if (typeof variant !== 'string') return null;
  const trimmed = variant.trim();
  if (!trimmed || trimmed.length > 64 || !/^[A-Za-z0-9_-]+$/.test(trimmed)) return null;
  return trimmed;
}

function interpret(value: unknown): { enabled: boolean; variant: string } {
  if (typeof value === 'boolean') return value ? { enabled: true, variant: 'dynamic' } : { enabled: false, variant: 'legacy' };
  if (typeof value === 'number') return value === 0 ? { enabled: false, variant: 'legacy' } : { enabled: true, variant: 'dynamic' };
  if (typeof value === 'string') {
    const text = value.trim().toLowerCase();
    if (['1', 'true', 'on', 'enabled', 'dynamic', 'treatment'].includes(text)) {
      return { enabled: true, variant: 'dynamic' };
    }
    return { enabled: false, variant: 'legacy' };
  }
  if (value && typeof value === 'object') {
    const record = value as Record<string, unknown>;
    if (record.killSwitch === true || record.kill_switch === true) return { enabled: false, variant: 'legacy' };
    const raw = record.enabled ?? record.value ?? record.on;
    const enabled = raw === undefined ? false : interpret(raw).enabled;
    if (!enabled) return { enabled: false, variant: 'legacy' };
    return { enabled: true, variant: sanitizeVariant(record.variant) ?? 'dynamic' };
  }
  return { enabled: false, variant: 'legacy' };
}

function lookup(root: Record<string, unknown>): unknown {
  if (EU_PAYMENTS_FLAG in root) return root[EU_PAYMENTS_FLAG];
  for (const bucket of [root.flags, root.featureFlags]) {
    if (bucket && typeof bucket === 'object' && !Array.isArray(bucket) && EU_PAYMENTS_FLAG in (bucket as object)) {
      return (bucket as Record<string, unknown>)[EU_PAYMENTS_FLAG];
    }
    if (Array.isArray(bucket)) {
      const match = bucket.find((row) => {
        if (!row || typeof row !== 'object') return false;
        const record = row as Record<string, unknown>;
        return record.key === EU_PAYMENTS_FLAG || record.name === EU_PAYMENTS_FLAG;
      });
      if (match) return match;
    }
  }
  return undefined;
}

/** A JSON object that omits the flag is the kill switch. Null means the payload is not an object. */
export function parseFeatureFlag(payload: unknown): { enabled: boolean; variant: string } | null {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return null;
  const value = lookup(payload as Record<string, unknown>);
  if (value === undefined) return { enabled: false, variant: 'legacy' };
  return interpret(value);
}

export function readFlagCache(storage: Storage, sessionId: string): FeatureFlagEvaluation | null {
  const raw = storage.getItem(cacheKey(sessionId));
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as FeatureFlagEvaluation;
    if (parsed.key !== EU_PAYMENTS_FLAG || typeof parsed.enabled !== 'boolean') return null;
    return {
      key: EU_PAYMENTS_FLAG,
      enabled: parsed.enabled,
      variant: parsed.enabled ? sanitizeVariant(parsed.variant) ?? 'dynamic' : 'legacy',
      source: 'cache',
    };
  } catch {
    return null;
  }
}

export function writeFlagCache(storage: Storage, sessionId: string, evaluation: FeatureFlagEvaluation) {
  storage.setItem(cacheKey(sessionId), JSON.stringify(evaluation));
}

function providerId(row: Record<string, unknown>): 'adyen' | 'worldpay' | null {
  const raw = row.providerId ?? row.provider ?? row.id;
  return raw === 'adyen' || raw === 'worldpay' ? raw : null;
}

function decodeProvider(row: unknown): CatalogProvider | null {
  if (!row || typeof row !== 'object') return null;
  const record = row as Record<string, unknown>;
  const id = providerId(record);
  if (!id) return null;
  const nameValue = record.name ?? record.label;
  const name = typeof nameValue === 'string' && nameValue.trim() ? nameValue : id === 'adyen' ? 'Adyen' : 'Worldpay';
  const single = record.method ?? record.rail;
  let method: 'card' | 'bank' | null = single === 'card' || single === 'bank' ? single : null;
  if (!method && Array.isArray(record.methods)) {
    const first = record.methods.find((item) => item === 'card' || item === 'bank');
    if (first === 'card' || first === 'bank') method = first;
  }
  if (!method) return null;
  return { id, name, method };
}

function isDynamic(root: Record<string, unknown>) {
  const marker = String(root.schema ?? root.model ?? '').trim().toLowerCase();
  if (marker === 'dynamic') return true;
  if (marker === 'legacy') return false;
  return Array.isArray(root.methods) && !('providers' in root);
}

function decodeCurrencies(value: unknown, dynamic: boolean): Array<'GBP' | 'EUR'> {
  if (!dynamic) return ['GBP'];
  const codes = Array.isArray(value)
    ? value.map((item) => (typeof item === 'string' ? item : (item as { code?: unknown })?.code))
    : [];
  const recognized: Array<'GBP' | 'EUR'> = [];
  for (const code of codes) {
    const normalized = String(code ?? '').trim().toUpperCase();
    if ((normalized === 'GBP' || normalized === 'EUR') && !recognized.includes(normalized)) {
      recognized.push(normalized);
    }
  }
  if (!recognized.includes('GBP')) recognized.unshift('GBP');
  return recognized;
}

/** Accepts the legacy two-provider document and the dynamic methods document. Never throws. */
export function decodeCatalog(payload: unknown): DecodedCatalog | null {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return null;
  const root = payload as Record<string, unknown>;
  const dynamic = isDynamic(root);
  const rows = dynamic && Array.isArray(root.methods) ? root.methods : Array.isArray(root.providers) ? root.providers : [];
  const recipients = Array.isArray(root.recipients)
    ? root.recipients.flatMap((row) => {
        if (!row || typeof row !== 'object') return [];
        const record = row as DecodedCatalog['recipients'][number];
        if (!record.id || !record.name) return [];
        return [record];
      })
    : [];
  return {
    schema: dynamic ? 'dynamic' : 'legacy',
    demoDate: typeof root.demoDate === 'string' ? root.demoDate : '',
    recipients,
    providers: rows.flatMap((row) => {
      const provider = decodeProvider(row);
      return provider ? [provider] : [];
    }),
    currencies: decodeCurrencies(root.currencies, dynamic),
  };
}

export function paymentMethodChoices(flag: FeatureFlagEvaluation | null, catalog: DecodedCatalog | null): CatalogProvider[] {
  if (!flag?.enabled) return LEGACY_PROVIDERS;
  return catalog && catalog.providers.length > 0 ? catalog.providers : LEGACY_PROVIDERS;
}

export function paymentTelemetryEvent(
  evaluation: Pick<FeatureFlagEvaluation, 'enabled' | 'variant'> | null,
  idempotencyKey: string,
  displayCurrency: string,
): PaymentTelemetryEvent {
  const enabled = evaluation?.enabled === true;
  const variant = enabled ? sanitizeVariant(evaluation?.variant) ?? 'dynamic' : 'legacy';
  const currency = enabled && displayCurrency === 'EUR' ? 'EUR' : 'GBP';
  return {
    action: 'payment.submit',
    flagKey: EU_PAYMENTS_FLAG,
    variant,
    currency,
    idempotencyKey,
    header: `${EU_PAYMENTS_FLAG}=${variant}`,
  };
}
