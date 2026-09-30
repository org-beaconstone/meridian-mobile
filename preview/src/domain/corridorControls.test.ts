import { describe, expect, it } from 'vitest';
import { CorridorControls, PAYMENTS_PAUSED_MESSAGE } from './corridorControls';

const euCatalog = {
  catalogVersion: 2,
  catalogs: [
    { version: 1, corridors: ['GB'] },
    { version: 2, corridors: ['GB', 'EU'] },
  ],
};

function ids(controls: CorridorControls, account = 'acct'): string[] {
  return controls.visibleMethods(account).map((method) => method.id);
}

describe('corridor flags and kill switch', () => {
  it('defaults to Adyen card and Worldpay bank on the GB corridor', () => {
    const controls = new CorridorControls();
    expect(ids(controls)).toEqual(['adyen-card-gb', 'worldpay-bank-gb']);
    expect(controls.visibleMethods('acct').every((method) => method.provider === 'adyen' || method.provider === 'worldpay')).toBe(
      true,
    );
  });

  it('gates multi-provider selection and the European corridor independently', () => {
    const controls = new CorridorControls();
    expect(
      controls.applyServerPayload({
        ...euCatalog,
        flags: { multi_provider_selection: false, european_corridor: true },
      }),
    ).toBe(true);
    expect(controls.flags.multiProviderSelection).toBe(false);
    expect(controls.flags.europeanCorridorEnabled).toBe(true);
    expect(ids(controls)).toEqual(['adyen-card-gb', 'adyen-card-eu']);

    controls.applyServerPayload({
      flags: { multi_provider_selection: true, european_corridor: false },
    });
    expect(controls.flags.multiProviderSelection).toBe(true);
    expect(controls.flags.europeanCorridorEnabled).toBe(false);
    expect(ids(controls)).toEqual(['adyen-card-gb', 'worldpay-bank-gb']);
    expect(controls.activeCatalog.version).toBe(2);
  });

  it('keeps European methods hidden during dark launch and records telemetry', () => {
    const controls = new CorridorControls();
    controls.applyServerPayload({
      ...euCatalog,
      flags: { multi_provider_selection: true, european_corridor: true, dark_launch: true },
    });
    expect(controls.resolve('acct').map((method) => method.corridor)).toEqual(['GB', 'GB']);
    expect(controls.resolve('acct')).toHaveLength(2);
    expect(controls.telemetry).toEqual([
      {
        generation: 1,
        accountId: 'acct',
        catalogVersion: 2,
        corridor: 'EU',
        europeanMethodsHidden: true,
      },
    ]);
  });

  it('limits the European corridor to controlled accounts', () => {
    const controls = new CorridorControls();
    controls.applyServerPayload({
      ...euCatalog,
      flags: { european_corridor: true, multi_provider_selection: true },
      controlledAccounts: ['controlled-eu'],
    });
    expect(ids(controls, 'controlled-eu')).toContain('adyen-card-eu');
    expect(ids(controls, 'everyone-else')).not.toContain('adyen-card-eu');

    controls.applyServerPayload({
      flags: { european_corridor: true, dark_launch: true, multi_provider_selection: true },
      canaryAccounts: ['controlled-eu'],
    });
    expect(ids(controls, 'controlled-eu')).not.toContain('adyen-card-eu');
    controls.resolve('controlled-eu');
    expect(controls.telemetry.at(-1)?.europeanMethodsHidden).toBe(true);
  });

  it('stops new intents immediately and still returns status and receipts', () => {
    const controls = new CorridorControls();
    const created = controls.createIntent({
      idempotencyKey: 'key-1',
      accountId: 'acct',
      recipientId: 'northline-studio',
      amountMinor: 2500,
      note: 'Studio',
      methodId: 'adyen-card-gb',
    });
    expect(created.ok).toBe(true);
    if (!created.ok) return;
    expect(controls.complete(created.intent.id, 'REF-1')?.amountMinor).toBe(2500);
    expect(controls.applyServerPayload({ flags: { payments_kill_switch: true } })).toBe(true);
    const blocked = controls.createIntent({
      idempotencyKey: 'key-2',
      accountId: 'acct',
      recipientId: 'northline-studio',
      amountMinor: 100,
      methodId: 'adyen-card-gb',
    });
    expect(blocked).toMatchObject({ ok: false, reason: 'KILL_SWITCH', message: PAYMENTS_PAUSED_MESSAGE });
    expect(controls.status(created.intent.id)).toBe('completed');
    expect(controls.receipt(created.intent.id)?.reference).toBe('REF-1');
    const retry = controls.createIntent({
      idempotencyKey: 'key-1',
      accountId: 'acct',
      recipientId: 'other',
      amountMinor: 1,
      methodId: 'worldpay-bank-gb',
    });
    expect(retry.ok && retry.intent.id).toBe(created.intent.id);
    expect(retry.ok && retry.intent.provider).toBe('adyen');
  });

  it('rolls the catalog back without invalidating an in-flight snapshot', () => {
    const controls = new CorridorControls();
    controls.applyServerPayload({
      ...euCatalog,
      flags: { european_corridor: true, multi_provider_selection: true },
    });
    const created = controls.createIntent({
      idempotencyKey: 'eu-key',
      accountId: 'acct',
      recipientId: 'northline-studio',
      amountMinor: 1_000_000,
      methodId: 'worldpay-bank-eu',
    });
    expect(created.ok).toBe(true);
    if (!created.ok) return;
    const snapshot = structuredClone(created.intent.snapshot);
    expect(
      controls.applyServerPayload({
        flags: { european_corridor: true, multi_provider_selection: true },
        catalogVersion: 1,
      }),
    ).toBe(true);
    expect(controls.activeCatalog.version).toBe(1);
    expect(controls.activeCatalog.methods.some((method) => method.id === 'worldpay-bank-eu')).toBe(false);
    expect(controls.intent(created.intent.id)?.snapshot).toEqual(snapshot);
    expect(controls.snapshotRemainsValid(created.intent.id)).toBe(true);
    expect(controls.status(created.intent.id)).toBe('inFlight');
    expect(controls.rollbackCatalog(99)).toBe(false);
    expect(controls.activeCatalog.version).toBe(1);
    expect(controls.rollbackCatalog(2)).toBe(true);
    expect(controls.intent(created.intent.id)?.snapshot.version).toBe(2);
  });

  it('ignores numeric flags and corrupt payloads', () => {
    const controls = new CorridorControls();
    controls.applyServerPayload({ flags: { payments_kill_switch: true } });
    expect(controls.applyServerPayload('nope')).toBe(false);
    expect(controls.applyServerPayload([])).toBe(false);
    expect(controls.flags.killSwitch).toBe(true);
    expect(controls.blocksNewIntent('fresh')).toBe(true);

    expect(
      controls.applyServerPayload({
        flags: {
          payments_kill_switch: 1,
          european_corridor: 1,
          dark_launch: 1,
          multi_provider_selection: 0,
        },
      }),
    ).toBe(true);
    expect(controls.flags.killSwitch).toBe(false);
    expect(controls.flags.europeanCorridorEnabled).toBe(false);
    expect(controls.flags.darkLaunch).toBe(false);
    expect(controls.flags.multiProviderSelection).toBe(false);
    expect(ids(controls)).toEqual(['adyen-card-gb']);

    controls.applyServerPayload({
      payments_kill_switch: true,
      flags: { payments_kill_switch: false },
      dark_launch: 'TRUE',
      european_corridor: 'true',
    });
    expect(controls.flags.killSwitch).toBe(false);
    expect(controls.flags.darkLaunch).toBe(true);
    expect(controls.flags.europeanCorridorEnabled).toBe(true);
  });

  it('rejects a hidden method and an out-of-range amount', () => {
    const controls = new CorridorControls();
    const hidden = controls.createIntent({
      idempotencyKey: 'hidden',
      accountId: 'acct',
      recipientId: 'northline-studio',
      amountMinor: 100,
      methodId: 'adyen-card-eu',
    });
    expect(hidden).toMatchObject({ ok: false, reason: 'METHOD_UNAVAILABLE' });
    expect(controls.intent('intent-1')).toBeUndefined();
    const amount = controls.createIntent({
      idempotencyKey: 'amount',
      accountId: 'acct',
      recipientId: 'northline-studio',
      amountMinor: 1_000_001,
      methodId: 'adyen-card-gb',
    });
    expect(amount).toMatchObject({ ok: false, reason: 'INVALID_AMOUNT' });
  });
});
