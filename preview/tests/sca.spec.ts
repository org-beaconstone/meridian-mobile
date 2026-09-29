import { expect, test } from '@playwright/test';

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
      category: 'Shopping',
      initials: 'NS',
      detail: 'Studio',
    },
  ],
  providers: [
    { id: 'adyen', name: 'Adyen', description: 'Card', methods: ['card'] },
    { id: 'worldpay', name: 'Worldpay', description: 'Bank', methods: ['bank'] },
  ],
};

test('browser companion rehearses SCA without sending the passcode', async ({ page }) => {
  const payments: { key: string | undefined; session: string | undefined; body: Record<string, unknown> }[] =
    [];
  await page.route('**/api/v1/**', async (route) => {
    const url = route.request().url();
    if (url.includes('/state')) return route.fulfill({ json: state });
    if (url.includes('/catalog')) return route.fulfill({ json: catalog });
    if (url.includes('/payments') && route.request().method() === 'POST') {
      const body = JSON.parse(route.request().postData() || '{}') as Record<string, unknown>;
      payments.push({
        key: route.request().headers()['idempotency-key'],
        session: route.request().headers()['x-rehearsal-session'],
        body,
      });
      if (!body.scaChallengeToken) {
        return route.fulfill({
          status: 202,
          json: {
            ok: false,
            code: 'SCA_STEP_UP_REQUIRED',
            challenge: { payload: 'ch_browser', expiresAt: '2099-01-01T00:00:00Z' },
          },
        });
      }
      return route.fulfill({
        json: {
          ok: true,
          state: { ...state, balance: 1244050 },
          transaction: {
            id: 'txn-sca',
            name: 'Northline Studio',
            amount: body.amountMinor,
            date: '2026-09-18',
            category: 'Shopping',
            status: 'completed',
            provider: 'adyen',
            reference: 'REF-SCA',
          },
        },
      });
    }
    return route.fulfill({ status: 404, json: { error: 'missing' } });
  });

  await page.goto('/');
  await expect(page.getByTestId('mobile-balance')).toBeVisible();
  await page.getByRole('button', { name: 'Pay', exact: true }).click();
  await page.getByLabel('Amount (GBP)').fill('40.00');
  await page.getByRole('button', { name: 'Review payment' }).click();
  await page.getByRole('button', { name: 'Confirm payment' }).click();
  await expect(page.getByTestId('sca-challenge')).toBeVisible();
  await expect(page.getByText('Confirm with Face ID / Fingerprint to authorize European payment')).toBeVisible();
  await expect(page.getByText(/Browser companion stand-in/)).toBeVisible();
  await expect(page.getByTestId('sca-amount')).toHaveText('£40.00');
  await expect(page.getByTestId('sca-recipient')).toContainText('Northline Studio');
  await page.getByLabel('Security passcode').fill('000000');
  await page.getByRole('button', { name: 'Verify passcode' }).click();
  await expect(page.getByRole('alert')).toHaveText(
    'Authentication challenge failed. Please verify with your passcode.',
  );
  await expect(page.getByTestId('sca-amount')).toHaveText('£40.00');
  await expect(page.getByTestId('sca-recipient')).toContainText('Northline Studio');
  await page.getByLabel('Security passcode').fill('135790');
  await page.getByRole('button', { name: 'Verify passcode' }).click();
  await expect(page.getByRole('heading', { name: 'Demo payment complete' })).toBeVisible();

  expect(payments).toHaveLength(2);
  expect(payments[0].key).toBeTruthy();
  expect(payments[0].key).toBe(payments[1].key);
  expect(payments[0].session).toBe('meridian-rehearsal');
  expect(payments[1].session).toBe('meridian-rehearsal');
  expect(payments[0].body.method).toBe('card');
  expect(payments[1].body.method).toBe('card');
  expect(payments[0].body.amountMinor).toBe(4000);
  expect(payments[0].body.scaChallengeToken).toBeUndefined();
  expect(payments[1].body.scaChallengeToken).toBe('ch_browser');
  expect(JSON.stringify(payments)).not.toContain('135790');
});

test('an expired challenge keeps the recipient and amount', async ({ page }) => {
  let posts = 0;
  await page.route('**/api/v1/**', async (route) => {
    const url = route.request().url();
    if (url.includes('/state')) return route.fulfill({ json: state });
    if (url.includes('/catalog')) return route.fulfill({ json: catalog });
    if (url.includes('/payments')) {
      posts += 1;
      return route.fulfill({
        status: 202,
        json: {
          ok: false,
          code: 'SCA_STEP_UP_REQUIRED',
          challengePayload: 'stale',
          expiresAt: '2000-01-01T00:00:00Z',
        },
      });
    }
    return route.fulfill({ status: 404, json: { error: 'missing' } });
  });
  await page.goto('/');
  await expect(page.getByTestId('mobile-balance')).toBeVisible();
  await page.getByRole('button', { name: 'Pay', exact: true }).click();
  await page.getByLabel('Amount (GBP)').fill('40.00');
  await page.getByRole('button', { name: 'Review payment' }).click();
  await page.getByRole('button', { name: 'Confirm payment' }).click();
  await expect(page.getByRole('alert')).toHaveText(
    'Authentication challenge failed. Please verify with your passcode.',
  );
  await expect(page.getByText('To Northline Studio')).toBeVisible();
  await expect(page.getByText('£40.00')).toBeVisible();
  expect(posts).toBe(1);
});
