export const paymentMethodUnavailableText =
  'This payment method is temporarily unavailable in your region.';

export type PaymentMethodKind = 'card' | 'bank';

export type CatalogProvider = {
  id: string;
  name: string;
  description?: string;
  methods: string[];
  availability?: string | null;
};

export type CorridorContext = { region: string; currency: string };

export const gbpCorridor: CorridorContext = { region: 'GB', currency: 'GBP' };

export type MethodOption = {
  id: string;
  method: PaymentMethodKind;
  title: string;
  selectable: boolean;
  helperText: string | null;
  accessibilityLabel: string;
};

export type PaymentMethodSheetModel = {
  loading: boolean;
  options: MethodOption[];
  placeholderCount: number;
};

const baselineMethods: { providerId: string; method: PaymentMethodKind; title: string }[] = [
  { providerId: 'adyen', method: 'card', title: 'Adyen Card' },
  { providerId: 'worldpay', method: 'bank', title: 'Worldpay' },
];

export function paymentMethodSheetModel(
  providers: CatalogProvider[] | null,
  corridor: CorridorContext = gbpCorridor,
): PaymentMethodSheetModel {
  if (providers == null) return { loading: true, options: [], placeholderCount: 2 };
  const corridorOpen = corridor.currency === 'GBP' && corridor.region === 'GB';
  const drafts: { id: string; method: PaymentMethodKind; title: string; selectable: boolean }[] =
    [];
  const seen = new Set<PaymentMethodKind>();
  for (const provider of providers) {
    const baseline = baselineMethods.find((item) => item.providerId === provider.id);
    if (!baseline || !provider.methods.includes(baseline.method) || seen.has(baseline.method))
      continue;
    seen.add(baseline.method);
    const status = (provider.availability ?? 'available').trim().toLowerCase();
    drafts.push({
      id: provider.id,
      method: baseline.method,
      title: baseline.title,
      selectable: corridorOpen && status === 'available',
    });
  }
  return {
    loading: false,
    placeholderCount: 0,
    options: drafts.map((draft, index) => ({
      ...draft,
      helperText: draft.selectable ? null : paymentMethodUnavailableText,
      accessibilityLabel: `Select ${draft.title}, radio button, ${index + 1} of ${drafts.length}`,
    })),
  };
}

export function submittablePaymentMethod(
  selected: PaymentMethodKind,
  model: PaymentMethodSheetModel,
): PaymentMethodKind | null {
  if (model.loading) return null;
  const option = model.options.find((item) => item.method === selected);
  if (!option?.selectable) return null;
  return selected;
}

export function paymentMethodBlockMessage(
  selected: PaymentMethodKind,
  model: PaymentMethodSheetModel,
): string | null {
  if (submittablePaymentMethod(selected, model)) return null;
  if (model.loading) return 'Payment methods are still loading.';
  return (
    model.options.find((item) => item.method === selected)?.helperText ??
    'Choose an available payment method.'
  );
}
