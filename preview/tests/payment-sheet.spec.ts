import { expect, test } from '@playwright/test';

const state = {
  version: 1,
  balance: 1248050,
  transactions: [],
  budgets: [{ category: 'Shopping', limit: 100000 }],
};

test('browser companion bottom sheet loads catalog rails', async ({ page }) => {
  let releaseCatalog: () => void = () => {};
  const catalogReady = new Promise<void>((resolve) => {
    releaseCatalog = resolve;
  });
  await page.route('**/api/v1/state', (route) => route.fulfill({ json: state }));
  await page.route('**/api/v1/catalog', async (route) => {
    await catalogReady;
    await route.fulfill({
      json: {
        demoDate: '2026-09-18',
        recipients: [
          {
            id: 'northline-studio',
            name: 'Northline Studio',
            initials: 'NS',
            detail: 'Design tools',
            category: 'Shopping',
            color: '#FF6B6B',
          },
        ],
        providers: [
          {
            id: 'adyen',
            name: 'Adyen',
            description: 'Card payment processor',
            methods: ['card'],
            status: 'available',
          },
          {
            id: 'worldpay',
            name: 'Worldpay',
            description: 'Bank payment processor',
            methods: ['bank'],
            status: 'unavailable',
          },
          {
            id: 'not-baseline',
            name: 'Not Shown',
            description: 'Ignored',
            methods: ['card'],
          },
        ],
      },
    });
  });

  await page.goto('/');
  await expect(page.getByText('Connected API', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Pay', exact: true }).click();
  await expect(page.getByLabel('Loading payment methods')).toBeVisible();
  releaseCatalog();
  await expect(page.getByRole('button', { name: 'Payment method, Debit card' })).toBeVisible();
  await expect(page.getByText('Not Shown')).toHaveCount(0);
  await page.getByRole('button', { name: 'Payment method, Debit card' }).click();
  const dialog = page.getByRole('dialog', { name: 'Payment method' });
  await expect(dialog).toBeVisible();
  await expect(
    dialog.getByRole('radio', { name: 'Select Debit card, radio button, 1 of 2' }),
  ).toBeChecked();
  const bank = dialog.getByRole('radio', { name: 'Select Bank payment, radio button, 2 of 2' });
  await expect(bank).toHaveAttribute('aria-disabled', 'true');
  await expect(bank).not.toBeChecked();
  await expect(
    dialog.getByText('This payment method is temporarily unavailable in your region.'),
  ).toBeVisible();
  await bank.click({ force: true });
  await expect(
    dialog.getByRole('radio', { name: 'Select Debit card, radio button, 1 of 2' }),
  ).toBeChecked();
  await expect(bank).not.toBeChecked();
  await page.getByRole('button', { name: 'Close payment methods' }).click();
  await expect(dialog).toBeHidden();
  await expect(page.getByText('Adyen card (UK debit, usually instant)')).toBeVisible();
});
