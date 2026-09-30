import { expect, test } from '@playwright/test';

const state = {
  version: 1,
  balance: 250000,
  transactions: [],
  budgets: [
    { category: 'Shopping', limit: 100000 },
    { category: 'Food & drink', limit: 80000 },
    { category: 'Transport', limit: 40000 },
    { category: 'Bills', limit: 60000 },
    { category: 'Lifestyle', limit: 30000 },
  ],
};

const catalog = {
  demoDate: '2026-09-18',
  recipients: [
    {
      id: 'northline-studio',
      name: 'Northline Studio',
      category: 'Shopping',
      initials: 'NS',
      detail: 'Design studio',
    },
  ],
  providers: [
    { id: 'adyen', name: 'Adyen', description: 'Card', methods: ['card'] },
    { id: 'other', name: 'Other', description: 'Unused', methods: ['card', 'bank'] },
    { id: 'worldpay', name: 'Worldpay', description: 'Bank', methods: ['bank'] },
  ],
};

test('payment screen keeps the Adyen and Worldpay baseline', async ({ page }) => {
  const keys: string[] = [];
  const methods: string[] = [];
  let attempts = 0;

  await page.route('**/api/v1/state', (route) =>
    route.fulfill({ json: state, headers: { 'content-type': 'application/json' } }),
  );
  await page.route('**/api/v1/catalog', (route) =>
    route.fulfill({ json: catalog, headers: { 'content-type': 'application/json' } }),
  );
  await page.route('**/api/v1/payments', async (route) => {
    const body = route.request().postDataJSON() as { method: string; amountMinor: number };
    methods.push(body.method);
    keys.push(route.request().headers()['idempotency-key']);
    attempts += 1;
    expect(body.amountMinor).toBe(1050);
    expect(route.request().headers()['x-rehearsal-session']).toBe('meridian-rehearsal');
    if (attempts === 1) {
      await route.fulfill({
        status: 202,
        json: {
          ok: false,
          error: 'Payment pending confirmation',
          code: 'PAYMENT_PENDING',
          paymentId: 'pay-1',
        },
      });
      return;
    }
    await route.fulfill({
      json: {
        ok: true,
        state,
        transaction: {
          id: 'tx-1',
          name: 'Northline Studio',
          amount: 1050,
          date: '2026-09-18',
          category: 'Shopping',
          status: 'completed',
          provider: 'worldpay',
          reference: 'ref-1',
        },
      },
    });
  });

  await page.goto('/');
  await expect(page.getByTestId('mobile-balance')).toBeVisible();
  await page.getByRole('button', { name: 'Pay', exact: true }).click();
  await expect(page.getByText('Adyen simulation')).toBeVisible();
  await expect(page.getByText('Worldpay simulation')).toBeVisible();
  await expect(page.getByText('Other', { exact: true })).toHaveCount(0);

  await page.getByText('Worldpay simulation').click();
  await page.getByLabel('Amount (GBP)').fill('10.50');
  await page.getByRole('button', { name: 'Review payment' }).click();
  await expect(page.getByText('Worldpay ·')).toBeVisible();
  await page.getByRole('button', { name: 'Confirm payment' }).click();
  await expect(page.getByRole('alert')).toContainText('Payment pending confirmation');
  await page.getByRole('button', { name: 'Confirm payment' }).click();
  await expect(page.getByRole('heading', { name: 'Demo payment complete' })).toBeVisible();

  expect(methods).toEqual(['bank', 'bank']);
  expect(keys).toHaveLength(2);
  expect(keys[0]).toBeTruthy();
  expect(keys[0]).toBe(keys[1]);
});
