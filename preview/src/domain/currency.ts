export function money(pence: number): string {
  return formatMinor(pence, 'GBP');
}

export function formatMinor(minor: number, currency: 'GBP' | 'EUR' = 'GBP'): string {
  return new Intl.NumberFormat(currency === 'EUR' ? 'en-IE' : 'en-GB', {
    style: 'currency',
    currency,
  }).format(minor / 100);
}
export function parsePence(value: string): number | null {
  if (!/^\d+(\.\d{1,2})?$/.test(value)) return null;
  const [whole, part = ''] = value.split('.');
  const amount = Number(whole) * 100 + Number(part.padEnd(2, '0'));
  return Number.isSafeInteger(amount) && amount > 0 && amount <= 1000000 ? amount : null;
}
