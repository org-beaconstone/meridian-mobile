import { expect, test } from '@playwright/test';

test('whiteboard sticky note colour palette', async ({ page }) => {
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('/');
  await page.getByRole('button', { name: 'Board', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Whiteboard' })).toBeVisible();
  await expect(page.getByText('Browser companion rehearsal')).toBeVisible();
  const palette = page.getByTestId('sticky-palette');
  await expect(palette.getByRole('radio')).toHaveCount(8);
  await expect(palette.getByRole('radio', { name: 'Yellow' })).toBeChecked();
  await palette.getByRole('radio', { name: 'Teal' }).check();
  await page.getByRole('textbox', { name: 'Sticky note', exact: true }).fill('Ship the colour palette');
  await page.getByRole('button', { name: 'Add sticky note' }).click();
  const note = page.getByTestId('sticky-note');
  await expect(note).toContainText('Ship the colour palette');
  await expect(note).toContainText('Teal');
  await expect(note).toHaveAttribute('data-colour', 'teal');
  await expect(note).toHaveCSS('background-color', 'rgb(198, 237, 230)');
  await page.getByRole('textbox', { name: 'Sticky note', exact: true }).fill('   ');
  await page.getByRole('button', { name: 'Add sticky note' }).click();
  await expect(page.getByRole('alert').filter({ hasText: 'Write a sticky note' })).toBeVisible();
  await expect(page.getByTestId('sticky-note')).toHaveCount(1);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  expect(errors).toEqual([]);
});
