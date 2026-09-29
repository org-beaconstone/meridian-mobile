export const PAYMENTS_PAUSED_MESSAGE =
  'New payments are paused. Status and receipts stay available.';

/** GB is the domestic rehearsal corridor. EU is the European corridor. */
export type PaymentCorridor = 'GB' | 'EU';
export type RailMethod = 'card' | 'bank';
export type RailProvider = 'adyen' | 'worldpay';

export interface CorridorMethod {
  id: string;
  provider: RailProvider;
  method: RailMethod;
  corridor: PaymentCorridor;
  label: string;
}

export const CORRIDOR_BASELINE: CorridorMethod[] = [
  {
    id: 'adyen-card-gb',
    provider: 'adyen',
    method: 'card',
    corridor: 'GB',
    label: 'Debit card · Adyen',
  },
  {
    id: 'worldpay-bank-gb',
    provider: 'worldpay',
    method: 'bank',
    corridor: 'GB',
    label: 'Bank payment · Worldpay',
  },
  {
    id: 'adyen-card-eu',
    provider: 'adyen',
    method: 'card',
    corridor: 'EU',
    label: 'Debit card · Adyen · European corridor',
  },
  {
    id: 'worldpay-bank-eu',
    provider: 'worldpay',
    method: 'bank',
    corridor: 'EU',
    label: 'Bank payment · Worldpay · European corridor',
  },
];

export interface CorridorFlags {
  multiProviderSelection: boolean;
  europeanCorridorEnabled: boolean;
  darkLaunch: boolean;
  killSwitch: boolean;
  canaryAccounts: string[];
}

export const REHEARSAL_FLAGS: CorridorFlags = {
  multiProviderSelection: true,
  europeanCorridorEnabled: false,
  darkLaunch: false,
  killSwitch: false,
  canaryAccounts: [],
};

export interface CatalogSnapshot {
  version: number;
  methods: CorridorMethod[];
}

export type IntentStatus = 'inFlight' | 'completed' | 'declined';

export interface IntentReceipt {
  reference: string;
  amountMinor: number;
  methodId: string;
  provider: RailProvider;
}

export interface PaymentIntentRecord {
  id: string;
  idempotencyKey: string;
  accountId: string;
  recipientId: string;
  amountMinor: number;
  note: string;
  methodId: string;
  provider: RailProvider;
  method: RailMethod;
  corridor: PaymentCorridor;
  snapshot: CatalogSnapshot;
  status: IntentStatus;
  receipt: IntentReceipt | null;
}

export interface DarkLaunchEvent {
  generation: number;
  accountId: string;
  catalogVersion: number;
  corridor: string;
  europeanMethodsHidden: boolean;
}

export type IntentRejection =
  | 'KILL_SWITCH'
  | 'METHOD_UNAVAILABLE'
  | 'INVALID_AMOUNT'
  | 'MISSING_IDEMPOTENCY_KEY';

export type IntentResult =
  | { ok: true; intent: PaymentIntentRecord }
  | { ok: false; reason: IntentRejection; message: string };

function rejection(reason: IntentRejection): IntentResult {
  const message =
    reason === 'KILL_SWITCH'
      ? PAYMENTS_PAUSED_MESSAGE
      : reason === 'METHOD_UNAVAILABLE'
        ? 'That payment method is not available.'
        : reason === 'INVALID_AMOUNT'
          ? 'Amount must be from 1 to 1000000 pence.'
          : 'Idempotency key is required.';
  return { ok: false, reason, message };
}

function methodsFor(corridors: PaymentCorridor[]): CorridorMethod[] {
  return CORRIDOR_BASELINE.filter((method) => corridors.includes(method.corridor));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function coerce(value: unknown): boolean | undefined {
  if (value === undefined) return undefined;
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') return value.toLowerCase() === 'true';
  return false;
}

function readFlag(root: Record<string, unknown>, key: string, fallback: boolean): boolean {
  const flags = isRecord(root.flags) ? root.flags : undefined;
  if (flags && key in flags) return coerce(flags[key]) ?? false;
  if (key in root) return coerce(root[key]) ?? false;
  return fallback;
}

function corridorFrom(raw: unknown): PaymentCorridor | null {
  if (typeof raw !== 'string') return null;
  const upper = raw.toUpperCase();
  if (upper === 'GB' || upper === 'EU') return upper;
  return null;
}

/**
 * Server-driven corridor flags, dark launch telemetry, the operational kill switch,
 * and catalog rollback. Applying a payload replaces the previous flags immediately.
 * In-flight intents keep the catalog snapshot copied at creation.
 */
export class CorridorControls {
  flags: CorridorFlags = { ...REHEARSAL_FLAGS, canaryAccounts: [] };
  activeCatalog: CatalogSnapshot;
  telemetry: DarkLaunchEvent[] = [];
  private history = new Map<number, CatalogSnapshot>();
  private intentsById = new Map<string, PaymentIntentRecord>();
  private intentIdByKey = new Map<string, string>();
  private generation = 0;
  private identity = 0;

  constructor() {
    const initial: CatalogSnapshot = { version: 1, methods: methodsFor(['GB']) };
    this.activeCatalog = initial;
    this.history.set(1, initial);
  }

  reset(): void {
    const fresh = new CorridorControls();
    this.flags = fresh.flags;
    this.activeCatalog = fresh.activeCatalog;
    this.history = fresh.history;
    this.telemetry = [];
    this.intentsById.clear();
    this.intentIdByKey.clear();
    this.generation = 0;
  }

  /** Returns false when the payload is not a config object. State is left unchanged. */
  applyServerPayload(payload: unknown): boolean {
    if (!isRecord(payload)) return false;
    this.flags = {
      multiProviderSelection: readFlag(payload, 'multi_provider_selection', true),
      europeanCorridorEnabled: readFlag(payload, 'european_corridor', false),
      darkLaunch: readFlag(payload, 'dark_launch', false),
      killSwitch: readFlag(payload, 'payments_kill_switch', false),
      canaryAccounts: stringList(payload),
    };
    this.generation += 1;
    if ('catalogs' in payload) this.install(payload.catalogs);
    if (typeof payload.catalogVersion === 'number' && Number.isInteger(payload.catalogVersion)) {
      this.activate(payload.catalogVersion);
    }
    return true;
  }

  publishCatalog(version: number, corridors: PaymentCorridor[]): boolean {
    const seen = corridors.filter((corridor, index) => corridors.indexOf(corridor) === index);
    if (!Number.isInteger(version) || version <= 0 || seen.length === 0) return false;
    const snapshot: CatalogSnapshot = { version, methods: methodsFor(seen) };
    this.history.set(version, snapshot);
    this.activeCatalog = snapshot;
    return true;
  }

  /** Activates a stored catalog version. Intent snapshots are not rewritten. */
  rollbackCatalog(version: number): boolean {
    return this.activate(version);
  }

  visibleMethods(accountId: string): CorridorMethod[] {
    const allowEurope = this.europeanMethodsVisible(accountId);
    return this.activeCatalog.methods.filter((method) => {
      if (method.corridor === 'EU' && !allowEurope) return false;
      if (!this.flags.multiProviderSelection && !(method.provider === 'adyen' && method.method === 'card')) {
        return false;
      }
      return true;
    });
  }

  /** Records one dark-launch telemetry event per flag generation and account. */
  resolve(accountId: string): CorridorMethod[] {
    const methods = this.visibleMethods(accountId);
    if (this.flags.darkLaunch) {
      const already = this.telemetry.some(
        (event) => event.generation === this.generation && event.accountId === accountId,
      );
      if (!already) {
        this.telemetry.push({
          generation: this.generation,
          accountId,
          catalogVersion: this.activeCatalog.version,
          corridor: 'EU',
          europeanMethodsHidden: !methods.some((method) => method.corridor === 'EU'),
        });
      }
    }
    return methods;
  }

  blocksNewIntent(idempotencyKey: string): boolean {
    if (this.intentIdByKey.has(idempotencyKey)) return false;
    return this.flags.killSwitch;
  }

  createIntent(input: {
    idempotencyKey: string;
    accountId: string;
    recipientId: string;
    amountMinor: number;
    note?: string;
    methodId: string;
  }): IntentResult {
    const existingId = this.intentIdByKey.get(input.idempotencyKey);
    if (existingId) {
      const existing = this.intentsById.get(existingId);
      if (existing) return { ok: true, intent: existing };
    }
    if (!input.idempotencyKey || input.idempotencyKey.length > 100) {
      return rejection('MISSING_IDEMPOTENCY_KEY');
    }
    if (this.flags.killSwitch) return rejection('KILL_SWITCH');
    if (!Number.isInteger(input.amountMinor) || input.amountMinor < 1 || input.amountMinor > 1_000_000) {
      return rejection('INVALID_AMOUNT');
    }
    const selected = this.visibleMethods(input.accountId).find((method) => method.id === input.methodId);
    if (!selected) return rejection('METHOD_UNAVAILABLE');
    this.identity += 1;
    const record: PaymentIntentRecord = {
      id: `intent-${this.identity}`,
      idempotencyKey: input.idempotencyKey,
      accountId: input.accountId,
      recipientId: input.recipientId,
      amountMinor: input.amountMinor,
      note: input.note ?? '',
      methodId: selected.id,
      provider: selected.provider,
      method: selected.method,
      corridor: selected.corridor,
      snapshot: structuredClone(this.activeCatalog),
      status: 'inFlight',
      receipt: null,
    };
    this.intentsById.set(record.id, record);
    this.intentIdByKey.set(input.idempotencyKey, record.id);
    return { ok: true, intent: record };
  }

  intent(id: string): PaymentIntentRecord | undefined {
    return this.intentsById.get(id);
  }

  status(intentId: string): IntentStatus | undefined {
    return this.intentsById.get(intentId)?.status;
  }

  receipt(intentId: string): IntentReceipt | null | undefined {
    return this.intentsById.get(intentId)?.receipt;
  }

  /** True when the intent's own snapshot still contains its method, whatever the live catalog is. */
  snapshotRemainsValid(intentId: string): boolean {
    const intent = this.intentsById.get(intentId);
    if (!intent) return false;
    return intent.snapshot.version > 0 && intent.snapshot.methods.some((method) => method.id === intent.methodId);
  }

  complete(intentId: string, reference: string): IntentReceipt | null {
    const intent = this.intentsById.get(intentId);
    if (!intent) return null;
    const receipt: IntentReceipt = {
      reference,
      amountMinor: intent.amountMinor,
      methodId: intent.methodId,
      provider: intent.provider,
    };
    intent.status = 'completed';
    intent.receipt = receipt;
    return receipt;
  }

  markDeclined(intentId: string): void {
    const intent = this.intentsById.get(intentId);
    if (!intent) return;
    intent.status = 'declined';
  }

  private europeanMethodsVisible(accountId: string): boolean {
    if (this.flags.darkLaunch) return false;
    if (!this.flags.europeanCorridorEnabled) return false;
    if (this.flags.canaryAccounts.length === 0) return true;
    return this.flags.canaryAccounts.includes(accountId);
  }

  private activate(version: number): boolean {
    const snapshot = this.history.get(version);
    if (!snapshot) return false;
    this.activeCatalog = snapshot;
    return true;
  }

  private install(value: unknown): void {
    if (!Array.isArray(value)) return;
    const next = new Map<number, CatalogSnapshot>();
    for (const item of value) {
      if (!isRecord(item) || typeof item.version !== 'number' || !Number.isInteger(item.version) || item.version <= 0) {
        continue;
      }
      if (!Array.isArray(item.corridors)) continue;
      const corridors: PaymentCorridor[] = [];
      for (const name of item.corridors) {
        const corridor = corridorFrom(name);
        if (corridor && !corridors.includes(corridor)) corridors.push(corridor);
      }
      if (corridors.length === 0) continue;
      next.set(item.version, { version: item.version, methods: methodsFor(corridors) });
    }
    if (next.size > 0) this.history = next;
  }
}

function stringList(root: Record<string, unknown>): string[] {
  const node = 'canaryAccounts' in root ? root.canaryAccounts : root.controlledAccounts;
  if (!Array.isArray(node)) return [];
  return node.filter((item): item is string => typeof item === 'string');
}
