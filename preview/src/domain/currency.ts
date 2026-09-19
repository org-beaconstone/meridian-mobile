export function money(pence: number): string {
  return new Intl.NumberFormat('en-GB', { style: 'currency', currency: 'GBP' }).format(pence / 100);
}
export function parsePence(value: string): number | null {
  if (!/^\d+(\.\d{1,2})?$/.test(value)) return null;
  const [whole, part = ''] = value.split('.');
  const amount = Number(whole) * 100 + Number(part.padEnd(2, '0'));
  return Number.isSafeInteger(amount) && amount > 0 && amount <= 1000000 ? amount : null;
}
