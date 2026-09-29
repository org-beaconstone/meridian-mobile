export const REGION_UNAVAILABLE =
  'This payment method is temporarily unavailable in your region.';

export type PaymentMethodId = 'card' | 'bank';

export type CatalogProvider = {
  id: string;
  name: string;
  description: string;
  methods: string[];
};

export type PaymentRail = {
  method: PaymentMethodId;
  providerId: 'adyen' | 'worldpay';
  title: string;
  badge: string;
  available: boolean;
  warning: string | null;
};

const baselineRails: Array<{
  providerId: PaymentRail['providerId'];
  method: PaymentMethodId;
  title: string;
  fallbackName: string;
}> = [
  { providerId: 'adyen', method: 'card', title: 'Debit card', fallbackName: 'Adyen' },
  { providerId: 'worldpay', method: 'bank', title: 'Bank payment', fallbackName: 'Worldpay' },
];

export function readProviders(catalog: unknown): CatalogProvider[] {
  if (!catalog || typeof catalog !== 'object' || !('providers' in catalog)) return [];
  const providers = (catalog as { providers?: unknown }).providers;
  if (!Array.isArray(providers)) return [];
  return providers.flatMap((item) => {
    if (!item || typeof item !== 'object') return [];
    const provider = item as {
      id?: unknown;
      name?: unknown;
      description?: unknown;
      methods?: unknown;
    };
    if (typeof provider.id !== 'string' || typeof provider.name !== 'string') return [];
    return [
      {
        id: provider.id,
        name: provider.name,
        description: typeof provider.description === 'string' ? provider.description : '',
        methods: Array.isArray(provider.methods)
          ? provider.methods.filter((method): method is string => typeof method === 'string')
          : [],
      },
    ];
  });
}

/** Adyen card and Worldpay bank are the only rails this companion will offer. */
export function resolvePaymentRails(providers: CatalogProvider[]): PaymentRail[] {
  return baselineRails.map((rail) => {
    const named = providers.find((provider) => provider.id === rail.providerId);
    const name = named?.name.trim() || rail.fallbackName;
    const match = named?.methods.includes(rail.method) ? named : undefined;
    if (!match) {
      return {
        method: rail.method,
        providerId: rail.providerId,
        title: rail.title,
        badge: `${rail.title} · ${name}`,
        available: false,
        warning: REGION_UNAVAILABLE,
      };
    }
    const detail = match.description.trim();
    return {
      method: rail.method,
      providerId: rail.providerId,
      title: rail.title,
      badge: detail ? `${rail.title} · ${match.name.trim() || name} (${detail})` : `${rail.title} · ${match.name.trim() || name}`,
      available: true,
      warning: null,
    };
  });
}

export function railAnnouncement(rail: PaymentRail, position: number, total: number): string {
  const base = `Select ${rail.title}, radio button, ${position} of ${total}`;
  return rail.available ? base : `${base}. ${rail.warning ?? REGION_UNAVAILABLE}`;
}
