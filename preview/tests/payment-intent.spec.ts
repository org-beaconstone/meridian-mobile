import { expect, test, type Request } from '@playwright/test';

const state = {
  version: 1,
  balance: 1248050,
  transactions: [],
  budgets: [{ category: 'Shopping', limit: 100000 }],
};
const catalog = {
  demoDate: '2026-09-18',
  recipients: [
    {
      id: 'northline-studio',
      name: 'Northline Studio',
      initials: 'NS',
      detail: 'Design tools & materials',
      category: 'Shopping',
      color: '#FF6B6B',
    },
  ],
  providers: [],
};

test('review confirms one payment intent and keeps it after success or decline', async ({ page }) => {
  const posts: Request[] = [];
  await page.route('**/api/v1/**', (route) => {
    const url = route.request().url();
    if (url.includes('/state')) return route.fulfill({ json: state });
    if (url.includes('/catalog')) return route.fulfill({ json: catalog });
    return route.fulfill({ status: 404, body: '' });
  });
  let release: () => void = () => {};
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  await page.route('**/api/v2/payment-intents', async (route) => {
    posts.push(route.request());
    await gate;
    const scenario = route.request().headers()['x-rehearsal-scenario'];
    if (scenario === 'declined') {
      await route.fulfill({
        status: 422,
        json: {
          ok: false,
          status: 'declined',
          intentId: 'pi_decline',
          code: 'DECLINED',
          error: 'The payment was declined',
        },
      });
      return;
    }
    await route.fulfill({
      json: { ok: true, status: 'succeeded', intentId: 'pi_browser' },
    });
  });

  await page.goto('/');
  await expect(page.getByText('Connected API', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Pay', exact: true }).click();
  await page.getByLabel('Amount (GBP)').fill('1.999');
  await page.getByRole('button', { name: 'Review payment' }).click();
  await expect(page.getByRole('alert')).toContainText('two decimals');

  await page.getByLabel('Amount (GBP)').fill('25.99');
  await page.getByRole('button', { name: 'Review payment' }).click();
  await expect(page.getByRole('alert')).toContainText('reference');

  await page.getByLabel('Local reference').fill('INV-1042');
  await page.getByRole('button', { name: 'Review payment' }).click();
  await expect(page.getByTestId('review-recipient')).toContainText('Northline Studio');
  await expect(page.getByTestId('review-amount')).toHaveText('£25.99');
  await expect(page.getByTestId('review-fees')).toHaveText('£0.39');
  await expect(page.getByTestId('review-method')).toHaveText('Debit card');
  await expect(page.getByTestId('review-bank')).toHaveText('Adyen');
  await expect(page.getByTestId('review-quote-expiry')).toContainText('UTC');
  await expect(page.getByTestId('review-consent')).toContainText('does not move real money');
  await expect(page.getByTestId('confirm-payment')).toBeDisabled();

  await page.getByRole('checkbox', { name: 'I agree to this payment' }).check();
  await expect(page.getByTestId('confirm-payment')).toBeEnabled();
  await page.evaluate(() => {
    const button = document.querySelector('[data-testid="confirm-payment"]') as HTMLButtonElement;
    button.click();
    button.click();
  });
  await expect.poll(() => posts.length).toBe(1);
  const body = posts[0].postData() ?? '';
  expect(body).toContain('"amountMinor":2599');
  expect(body).toContain('"provider":"adyen"');
  expect(posts[0].headers()['x-rehearsal-session']).toBe('meridian-rehearsal');
  expect(posts[0].headers()['idempotency-key']).toMatch(
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
  );
  expect(posts[0].headers()['x-payload-hash']).toHaveLength(64);
  release();
  await expect(page.getByTestId('intent-outcome')).toContainText('pi_browser');
  await expect(page.getByTestId('intent-outcome')).toContainText('not submitted again');
  await expect(page.getByTestId('confirm-payment')).toHaveCount(0);
  expect(posts).toHaveLength(1);

  await page.getByRole('button', { name: 'New payment' }).click();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByLabel('Payment scenario').selectOption('declined');
  await page.getByRole('button', { name: 'Pay', exact: true }).click();
  await page.getByLabel('Amount (GBP)').fill('8.00');
  await page.getByLabel('Local reference').fill('BANK-1');
  await page.getByRole('radio', { name: /Bank payment/ }).check();
  await page.getByRole('button', { name: 'Review payment' }).click();
  await expect(page.getByTestId('review-fees')).toHaveText('£0.00');
  await expect(page.getByTestId('review-method')).toHaveText('Bank payment');
  await expect(page.getByTestId('review-bank')).toHaveText('Worldpay');
  await page.getByRole('checkbox', { name: 'I agree to this payment' }).check();
  const before = posts.length;
  await page.getByTestId('confirm-payment').click();
  await expect(page.getByTestId('intent-outcome')).toContainText('pi_decline');
  await expect(page.getByRole('alert')).toContainText('stays closed');
  expect(posts).toHaveLength(before + 1);
  expect(posts.at(-1)?.postData()).toContain('"provider":"worldpay"');
  expect(posts.at(-1)?.headers()['x-rehearsal-scenario']).toBe('declined');
  await page.getByTestId('confirm-payment').count().then((count) => expect(count).toBe(0));
});
