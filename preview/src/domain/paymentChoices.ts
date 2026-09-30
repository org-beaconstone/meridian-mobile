export type PaymentChoice = {
  id: 'adyen' | 'worldpay';
  method: 'card' | 'bank';
  name: string;
  label: string;
};

type LooseProvider = { id?: unknown; name?: unknown; methods?: unknown };

function catalogName(
  providers: LooseProvider[],
  id: string,
  method: string,
  fallback: string,
): string {
  const found = providers.find(
    (provider) =>
      provider.id === id &&
      Array.isArray(provider.methods) &&
      provider.methods.includes(method) &&
      typeof provider.name === 'string' &&
      provider.name.trim().length > 0,
  );
  return typeof found?.name === 'string' ? found.name.trim() : fallback;
}

/** Adyen card and Worldpay bank only. Any other catalog id is ignored. */
export function baselinePaymentChoices(providers?: unknown): PaymentChoice[] {
  const list = Array.isArray(providers) ? (providers as LooseProvider[]) : [];
  const cardName = catalogName(list, 'adyen', 'card', 'Adyen');
  const bankName = catalogName(list, 'worldpay', 'bank', 'Worldpay');
  return [
    { id: 'adyen', method: 'card', name: cardName, label: `Debit card · ${cardName}` },
    { id: 'worldpay', method: 'bank', name: bankName, label: `Bank payment · ${bankName}` },
  ];
}
