import { expect, test } from '@playwright/test';

test('session banner stays on payment and authentication without clearing entered details', async ({
  page,
}) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'Account', exact: true }).click();
  const banner = page.getByTestId('session-banner');
  await expect(banner).toContainText('Session active');
  await page.getByLabel('Preview session state').selectOption('expiring');
  await expect(banner.getByRole('button', { name: 'Refresh session' })).toBeVisible();
  await expect(banner).toContainText('remaining');
  await page.getByLabel('Preview session state').selectOption('expired');
  await expect(banner).toContainText('Entered payment details are still here');
  await page.getByRole('button', { name: 'Pay', exact: true }).click();
  await expect(page.getByTestId('session-banner')).toContainText('Session expired');

  const amount = page.getByLabel('Amount (GBP)');
  const reference = page.getByLabel('Reference');
  const formReady = await amount
    .waitFor({ state: 'visible', timeout: 8000 })
    .then(() => true)
    .catch(() => false);

  if (formReady) {
    await amount.fill('18.40');
    await reference.fill('Kept during session recovery');
    await page.getByRole('button', { name: 'Account', exact: true }).click();
    await page.getByLabel('Preview session state').selectOption('unknown');
    await page.getByRole('button', { name: 'Pay', exact: true }).click();
    await expect(page.getByTestId('session-banner')).toContainText('Session unknown');
    await expect(page.getByTestId('session-banner')).toContainText(
      'Your payment details stay on this screen',
    );
    await expect(amount).toHaveValue('18.40');
    await expect(reference).toHaveValue('Kept during session recovery');
    await page.getByRole('button', { name: 'Try again' }).click();
    await expect(page.getByTestId('session-banner')).toContainText('Session active');
    await expect(amount).toHaveValue('18.40');
    await expect(reference).toHaveValue('Kept during session recovery');
    await expect(page.getByRole('status')).toContainText('Payment details are unchanged');
  } else {
    await page.getByRole('button', { name: 'Sign in' }).click();
    await expect(page.getByTestId('session-banner')).toContainText('Session active');
    await expect(page.getByRole('status')).toContainText('Payment details are unchanged');
  }
});
