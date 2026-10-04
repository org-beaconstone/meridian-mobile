import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

test('session banner warns, refreshes in place, and blocks only after expiry', async ({ page }) => {
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  const states = [
    ['active', 'Session active.', 'rgb(239, 255, 214)', 'rgb(76, 107, 31)'],
    ['expiring', 'Session expiring soon. Tap to extend.', 'rgb(255, 245, 219)', 'rgb(158, 76, 0)'],
    ['elsewhere', 'Session active on another device.', 'rgb(233, 242, 254)', 'rgb(21, 88, 188)'],
    ['signed-out', 'Signed out.', 'rgb(255, 236, 235)', 'rgb(174, 46, 36)'],
  ] as const;
  for (const [query, text, background, foreground] of states) {
    await page.goto(`/?session=${query}`);
    const banner = page.getByTestId('session-status-banner');
    await expect(banner).toHaveText(text);
    await expect(banner).toHaveCSS('background-color', background);
    await expect(banner).toHaveCSS('color', foreground);
    await expect(page.getByRole('alertdialog')).toHaveCount(0);
    const contrast = await new AxeBuilder({ page })
      .include('[data-testid=session-status-banner]')
      .withRules(['color-contrast'])
      .analyze();
    expect(contrast.violations).toEqual([]);
  }

  await page.goto('/?session=expiring');
  const banner = page.getByTestId('session-status-banner');
  await expect(banner).toHaveAttribute('data-background-token', 'color.background.warning');
  await expect(banner).toHaveAttribute('data-foreground-token', 'color.text.warning');

  await page.getByRole('button', { name: 'Pay', exact: true }).click();
  await page.getByLabel('Amount (GBP)').fill('18.25');
  await page.getByLabel('Reference').fill('Studio rent');
  await page.getByRole('radio', { name: /Worldpay/ }).check();
  await banner.click();
  await expect(page.getByLabel('Amount (GBP)')).toHaveValue('18.25');
  await expect(page.getByLabel('Reference')).toHaveValue('Studio rent');
  await expect(page.getByRole('radio', { name: /Worldpay/ })).toBeChecked();
  await expect(banner).toHaveText('Session active.');
  await expect(page.getByRole('alertdialog')).toHaveCount(0);

  await page.getByText('Browser companion session controls').click();
  await page.getByRole('button', { name: 'Expire session' }).click();
  const dialog = page.getByRole('alertdialog');
  await expect(dialog).toBeVisible();
  await expect(dialog).toContainText('Session expired');
  await expect(page.getByTestId('session-status-banner')).toHaveCount(0);
  await expect(page.getByLabel('Amount (GBP)')).toHaveValue('18.25');
  await expect(page.getByLabel('Reference')).toHaveValue('Studio rent');
  await page.keyboard.press('Escape');
  await expect(dialog).toBeVisible();
  await page.getByRole('button', { name: 'Sign in again' }).click();
  await expect(dialog).toHaveCount(0);
  await expect(page.getByTestId('session-status-banner')).toHaveText('Session active.');
  await expect(page.getByLabel('Amount (GBP)')).toHaveValue('18.25');
  await expect(page.getByLabel('Reference')).toHaveValue('Studio rent');
  await expect(page.getByRole('radio', { name: /Worldpay/ })).toBeChecked();

  await page.getByRole('button', { name: 'Sign out' }).click();
  await expect(page.getByTestId('session-status-banner')).toHaveText('Signed out.');
  await expect(page.getByRole('alertdialog')).toHaveCount(0);
  await page.getByRole('button', { name: 'Active on another device' }).click();
  await expect(page.getByTestId('session-status-banner')).toHaveText(
    'Session active on another device.',
  );
  await expect(page.getByLabel('Amount (GBP)')).toHaveValue('18.25');
  expect(errors).toEqual([]);
});
