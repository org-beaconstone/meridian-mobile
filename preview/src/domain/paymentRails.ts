/** Browser companion mirror of the native payment-rail resolver. Not a device build. */

export const REGIONAL_UNAVAILABILITY_WARNING =
  'This payment method is temporarily unavailable in your region.';

export const ADYEN_CARD_TITLE = 'Debit card';
export const ADYEN_CARD_BADGE = 'Adyen card (UK debit, usually instant)';
export const WORLDPAY_BANK_TITLE = 'Bank payment';
export const WORLDPAY_BANK_BADGE = 'Worldpay bank transfer (Free, arrives next working day)';

export type RailAvailability = 'available' | 'degraded' | 'unavailable';
export type CatalogMethod = 'card' | 'bank';

export type CatalogProvider = {
  id: string;
  name: string;
  description?: string;
  methods?: string[];
  status?: string | null;
};

export type PaymentRail = {
  id: string;
  providerId: 'adyen' | 'worldpay';
  method: CatalogMethod;
  title: string;
  badge: string;
  availability: RailAvailability;
  selectable: boolean;
  warning: string | null;
  position: number;
  total: number;
  announcement: string;
};

export function paymentOptionAnnouncement(title: string, index: number, total: number): string {
  return `Select ${title}, radio button, ${index} of ${total}`;
}

function parseAvailability(status: string | null | undefined): RailAvailability {
  const value = status?.trim().toLowerCase() ?? '';
  if (value === '' || value === 'available' || value === 'online') return 'available';
  if (value === 'degraded') return 'degraded';
  return 'unavailable';
}

function baseline(id: string, method: string) {
  const provider = id.trim().toLowerCase();
  const rail = method.trim().toLowerCase();
  if (provider === 'adyen' && rail === 'card') {
    return {
      providerId: 'adyen' as const,
      method: 'card' as const,
      title: ADYEN_CARD_TITLE,
      badge: ADYEN_CARD_BADGE,
    };
  }
  if (provider === 'worldpay' && rail === 'bank') {
    return {
      providerId: 'worldpay' as const,
      method: 'bank' as const,
      title: WORLDPAY_BANK_TITLE,
      badge: WORLDPAY_BANK_BADGE,
    };
  }
  return null;
}

/** Only Adyen card and Worldpay bank are offered. Any other catalog provider is ignored. */
export function resolvePaymentRails(providers: CatalogProvider[]): PaymentRail[] {
  const partial: Array<Omit<PaymentRail, 'position' | 'total' | 'announcement'>> = [];
  const seen = new Set<string>();
  for (const provider of providers) {
    for (const methodName of provider.methods ?? []) {
      const match = baseline(provider.id, methodName);
      if (!match) continue;
      const key = `${match.providerId}:${match.method}`;
      if (seen.has(key)) continue;
      seen.add(key);
      const availability = parseAvailability(provider.status);
      partial.push({
        id: `${match.providerId}-${match.method}`,
        providerId: match.providerId,
        method: match.method,
        title: match.title,
        badge: match.badge,
        availability,
        selectable: availability === 'available',
        warning: availability === 'available' ? null : REGIONAL_UNAVAILABILITY_WARNING,
      });
    }
  }
  return partial.map((rail, index) => ({
    ...rail,
    position: index + 1,
    total: partial.length,
    announcement: paymentOptionAnnouncement(rail.title, index + 1, partial.length),
  }));
}
