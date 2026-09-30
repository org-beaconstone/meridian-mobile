import { expect, test, type Page, type Route } from '@playwright/test';

const state = {
  version: 1,
  balance: 1248050,
  transactions: [],
  budgets: [
    { category: 'Shopping', limit: 100000 },
    { category: 'Food & drink', limit: 80000 },
    { category: 'Transport', limit: 40000 },
    { category: 'Bills', limit: 120000 },
    { category: 'Lifestyle', limit: 50000 },
  ],
};

const catalog = {
  demoDate: '2026-09-18',
  recipients: [
    {
      id: 'northline-studio',
      name: 'Northline Studio',
      initials: 'NS',
      detail: 'Design tools',
      category: 'Shopping',
      color: '#142C35',
    },
  ],
  providers: [
    { id: 'adyen', name: 'Adyen', description: 'Card', methods: ['card'] },
    { id: 'worldpay', name: 'Worldpay', description: 'Bank', methods: ['bank'] },
  ],
};

async function json(route: Route, body: unknown, status = 200) {
  await route.fulfill({
    status,
    contentType: 'application/json',
    body: JSON.stringify(body),
  });
}

async function installLedger(page: Page) {
  await page.route('**/api/v1/state', (route) => json(route, state));
  await page.route('**/api/v1/catalog', (route) => json(route, catalog));
}

test('status checks resume after reload and a decline is not submitted again', async ({ page }) => {
  let posts = 0;
  await installLedger(page);
  await page.route('**/api/v1/payments', async (route) => {
    posts += 1;
    await json(
      route,
      {
        ok: false,
        error: 'Payment pending confirmation. Do not create another payment.',
        code: 'PAYMENT_PENDING',
        paymentId: 'pi-restart',
      },
      202,
    );
  });
  let intentGets = 0;
  await page.route('**/api/v2/payment-intents/pi-restart', async (route) => {
    expect(route.request().method()).toBe('GET');
    intentGets += 1;
    if (intentGets < 3) {
      await json(route, {
        id: 'pi-restart',
        status: intentGets === 1 ? 'processing' : 'pending',
        amountMinor: 1500,
        currency: 'GBP',
        recipientId: 'northline-studio',
        recipientName: 'Northline Studio',
      });
      return;
    }
    await json(route, {
      id: 'pi-restart',
      status: 'succeeded',
      amountMinor: 1500,
      currency: 'GBP',
      recipientId: 'northline-studio',
      recipientName: 'Northline Studio',
      method: 'card',
      provider: 'adyen',
      note: 'Materials',
      supportReference: 'SUP-140-7781',
      transaction: {
        id: 'pi-restart',
        reference: 'SUP-140-7781',
        recipientId: 'northline-studio',
        name: 'Northline Studio',
        category: 'Shopping',
        amount: 1500,
        date: '2026-09-18',
        provider: 'adyen',
        method: 'card',
        status: 'completed',
        note: 'Materials',
      },
    });
  });

  await page.goto('/');
  await expect(page.getByTestId('mobile-balance')).toBeVisible();
  await page.getByRole('button', { name: 'Pay', exact: true }).click();
  await page.getByLabel('Amount (GBP)').fill('15.00');
  await page.getByLabel('Reference').fill('Materials');
  await page.getByRole('button', { name: 'Review payment' }).click();
  await page.getByRole('button', { name: 'Confirm payment' }).click();
  await expect(page.getByTestId('status-checking')).toBeVisible();
  expect(posts).toBe(1);

  await page.reload();
  await expect(page.getByTestId('payment-receipt')).toBeVisible({ timeout: 15000 });
  await expect(page.getByTestId('support-reference')).toHaveText('SUP-140-7781');
  await expect(page.getByTestId('payment-receipt')).toContainText('Northline Studio');
  await expect(page.getByTestId('payment-receipt')).toContainText('£15.00');
  await expect(page.getByTestId('payment-receipt')).toContainText('Materials');
  await expect(page.getByTestId('payment-receipt')).toContainText('Adyen');
  expect(posts).toBe(1);
  expect(intentGets).toBeGreaterThan(0);
  await expect(page.getByRole('button', { name: 'Confirm payment' })).toHaveCount(0);
});

test('a terminal decline stays on screen and is not posted again', async ({ page }) => {
  let posts = 0;
  await installLedger(page);
  await page.route('**/api/v1/payments', async (route) => {
    posts += 1;
    await json(
      route,
      {
        ok: false,
        error: 'Payment declined. No debit was made.',
        code: 'PAYMENT_DECLINED',
      },
      422,
    );
  });
  await page.route('**/api/v2/**', () => {
    throw new Error('a declined payment must not be polled into another submission');
  });

  await page.goto('/');
  await expect(page.getByTestId('mobile-balance')).toBeVisible();
  await page.getByRole('button', { name: 'Pay', exact: true }).click();
  await page.getByLabel('Amount (GBP)').fill('15.00');
  await page.getByRole('button', { name: 'Review payment' }).click();
  await page.getByRole('button', { name: 'Confirm payment' }).click();
  await expect(page.getByTestId('payment-declined')).toContainText('will not be submitted again');
  await page.waitForTimeout(600);
  expect(posts).toBe(1);
  await expect(page.getByRole('button', { name: 'Confirm payment' })).toHaveCount(0);

  await page.reload();
  await expect(page.getByTestId('payment-declined')).toBeVisible();
  expect(posts).toBe(1);
});
