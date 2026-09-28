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
      detail: 'Design tools',
    },
  ],
  providers: [
    { id: 'adyen', name: 'Adyen', description: 'Card', methods: ['card'] },
    { id: 'worldpay', name: 'Worldpay', description: 'Bank', methods: ['bank'] },
  ],
};

test('SCA step-up keeps the payment and resubmits the original key', async ({ page }) => {
  const payments: { key: string | undefined; body: Record<string, unknown> }[] = [];
  await page.route('**/api/v1/**', async (route) => {
    const request = route.request();
    const url = request.url();
    if (url.includes('/state')) {
      await route.fulfill({ json: state });
      return;
    }
    if (url.includes('/catalog')) {
      await route.fulfill({ json: catalog });
      return;
    }
    if (url.includes('/payments') && request.method() === 'POST') {
      const body = request.postDataJSON() as Record<string, unknown>;
      const key = request.headers()['idempotency-key'];
      payments.push({ key, body });
      if (!body.scaChallengeToken) {
        await route.fulfill({
          status: 202,
          contentType: 'application/json',
          json: {
            ok: false,
            code: 'SCA_STEP_UP_REQUIRED',
            challenge: {
              payload: 'challenge-payload',
              expiresAt: '2099-01-01T00:00:00Z',
              scaChallengeToken: 'token-123',
            },
          },
        });
        return;
      }
      await route.fulfill({
        json: {
          ok: true,
          state: { ...state, balance: 1244050 },
          transaction: {
            id: 'txn-sca',
            name: 'Northline Studio',
            amount: 4000,
            date: '2026-09-28',
            category: 'Shopping',
            status: 'completed',
            provider: 'adyen',
            reference: 'REF-SCA',
          },
        },
      });
      return;
    }
    await route.fulfill({ status: 404, json: { error: 'not found' } });
  });

  await page.goto('/');
  await expect(page.getByTestId('mobile-balance')).toBeVisible();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByLabel('Rehearsal security passcode').fill('135790');
  await page.getByRole('button', { name: 'Pay', exact: true }).click();
  await page.getByLabel('Amount (GBP)').fill('40.00');
  await page.getByRole('button', { name: 'Review payment' }).click();
  await page.getByRole('button', { name: 'Confirm payment' }).click();

  await expect(
    page.getByRole('heading', {
      name: 'Confirm with Face ID / Fingerprint to authorize European payment',
    }),
  ).toBeVisible();
  await expect(page.getByTestId('sca-recipient')).toContainText('Northline Studio');
  await expect(page.getByTestId('sca-amount')).toHaveText('£40.00');
  await page.getByRole('button', { name: 'Use security passcode' }).click();
  await page.getByLabel('Security passcode').fill('000000');
  await page.getByRole('button', { name: 'Verify passcode' }).click();
  await expect(page.getByRole('alert')).toHaveText(
    'Authentication challenge failed. Please verify with your passcode.',
  );
  await expect(page.getByTestId('sca-recipient')).toContainText('Northline Studio');
  await expect(page.getByTestId('sca-amount')).toHaveText('£40.00');
  expect(payments).toHaveLength(1);
  expect(payments[0].body.scaChallengeToken).toBeUndefined();

  await page.getByLabel('Security passcode').fill('135790');
  await page.getByRole('button', { name: 'Verify passcode' }).click();
  await expect(page.getByRole('heading', { name: 'Demo payment complete' })).toBeVisible();
  expect(payments).toHaveLength(2);
  expect(payments[0].key).toBeTruthy();
  expect(payments[1].key).toBe(payments[0].key);
  expect(payments[1].body).toMatchObject({
    recipientId: 'northline-studio',
    amountMinor: 4000,
    method: 'card',
    scaChallengeToken: 'token-123',
  });
  expect(payments[0].body.method).toBe('card');
  expect(payments[1].body.method).toBe('card');
});

test('expired SCA challenge shows the failure copy and keeps the amount', async ({ page }) => {
  await page.route('**/api/v1/**', async (route) => {
    const request = route.request();
    const url = request.url();
    if (url.includes('/state')) {
      await route.fulfill({ json: state });
      return;
    }
    if (url.includes('/catalog')) {
      await route.fulfill({ json: catalog });
      return;
    }
    if (url.includes('/payments') && request.method() === 'POST') {
      await route.fulfill({
        status: 202,
        contentType: 'application/json',
        json: {
          ok: false,
          code: 'SCA_STEP_UP_REQUIRED',
          challenge: {
            payload: 'stale-payload',
            expiresAt: '2000-01-01T00:00:00Z',
            scaChallengeToken: 'stale-token',
          },
        },
      });
      return;
    }
    await route.fulfill({ status: 404, json: { error: 'not found' } });
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
  await expect(page.getByTestId('sca-recipient')).toContainText('Northline Studio');
  await expect(page.getByTestId('sca-amount')).toHaveText('£40.00');
  await expect(page.getByRole('button', { name: 'Confirm payment' })).toBeVisible();
});
