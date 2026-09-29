import { useEffect, useRef, useState } from 'react';
import './index.css';
import { formatMinor, money, parsePence as pence } from './domain/currency';
import {
  type CatalogProvider,
  type CurrencyCode,
  evaluateMobileEuPaymentsFlag,
  GBP_BASELINE,
  reconcileSelection,
  resolvePaymentSurface,
  type PaymentSurface,
} from './domain/featureGate';

type Category = 'Shopping' | 'Food & drink' | 'Transport' | 'Bills' | 'Lifestyle';
type Transaction = {
  id: string;
  name: string;
  amount: number;
  date: string;
  category: Category;
  status: string;
  provider: string;
  reference: string;
};
type State = {
  version: number;
  balance: number;
  transactions: Transaction[];
  budgets: { category: Category; limit: number }[];
};
type Recipient = { id: string; name: string; category: Category; initials: string; detail: string };
class RequestError extends Error {
  constructor(
    message: string,
    public code: string,
  ) {
    super(message);
  }
}
async function request(room: string, path: string, method = 'GET', body?: unknown, key?: string) {
  let response: Response;
  try {
    response = await fetch('/api/v1' + path, {
      method,
      headers: {
        'Content-Type': 'application/json',
        'X-Rehearsal-Session': room,
        ...(key ? { 'Idempotency-Key': key } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(15000),
    });
  } catch {
    throw new RequestError(
      'Connection lost. Outcome may be unknown. Retry this same payment after reconnecting.',
      'NETWORK_ERROR',
    );
  }
  const data = await response.json();
  if (!response.ok)
    throw new RequestError(data.error || `HTTP ${response.status}`, data.code || 'HTTP_ERROR');
  return data;
}
async function readEuFlag(room: string): Promise<boolean> {
  try {
    const response = await fetch('/api/v1/config', {
      headers: {
        Accept: 'application/json',
        'X-Rehearsal-Session': room,
      },
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) return false;
    return evaluateMobileEuPaymentsFlag(await response.json());
  } catch {
    return false;
  }
}
function bankState(value: unknown): State {
  const v = value as State;
  if (
    !v ||
    v.version !== 1 ||
    !Number.isSafeInteger(v.balance) ||
    v.balance < 0 ||
    !Array.isArray(v.transactions) ||
    !Array.isArray(v.budgets) ||
    v.budgets.some((b) => !Number.isSafeInteger(b.limit) || b.limit <= 0)
  )
    throw new Error('Invalid API state');
  return v;
}
export default function App() {
  const [room, setRoom] = useState('meridian-rehearsal');
  const [roomInput, setRoomInput] = useState(room);
  const [state, setState] = useState<State | null>(null);
  const [recipients, setRecipients] = useState<Recipient[]>([]);
  const [connected, setConnected] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [page, setPage] = useState<'Home' | 'Pay' | 'History' | 'Settings'>('Home');
  const [recipient, setRecipient] = useState('northline-studio');
  const [amount, setAmount] = useState('');
  const [note, setNote] = useState('');
  const [currency, setCurrency] = useState<CurrencyCode>('GBP');
  const [railId, setRailId] = useState(GBP_BASELINE[0].id);
  const [surface, setSurface] = useState<PaymentSurface>(
    () => resolvePaymentSurface(false, null, GBP_BASELINE).surface,
  );
  const [step, setStep] = useState<'details' | 'review' | 'done'>('details');
  const [scenario, setScenario] = useState('success');
  const [busy, setBusy] = useState(false);
  const [receipt, setReceipt] = useState<Transaction | null>(null);
  const [budgetCategory, setBudgetCategory] = useState<Category>('Shopping');
  const [budgetAmount, setBudgetAmount] = useState('1000');
  const epoch = useRef(0),
    revision = useRef(0),
    mutating = useRef(false),
    paymentKey = useRef(crypto.randomUUID()),
    currencyRef = useRef<CurrencyCode>('GBP'),
    railRef = useRef(GBP_BASELINE[0].id),
    stepRef = useRef(step),
    cacheRef = useRef(GBP_BASELINE);
  currencyRef.current = currency;
  railRef.current = railId;
  stepRef.current = step;
  useEffect(() => {
    const generation = ++epoch.current;
    let closed = false;
    let timer: ReturnType<typeof setTimeout>;
    setState(null);
    setConnected(false);
    setError('');
    cacheRef.current = GBP_BASELINE;
    currencyRef.current = 'GBP';
    railRef.current = GBP_BASELINE[0].id;
    setCurrency('GBP');
    setRailId(GBP_BASELINE[0].id);
    setSurface(resolvePaymentSurface(false, null, GBP_BASELINE).surface);
    function applyFlag(flag: boolean, providers: CatalogProvider[] | null) {
      const resolved = resolvePaymentSurface(flag, providers, cacheRef.current);
      cacheRef.current = resolved.cachedGbp;
      setSurface(resolved.surface);
      const next = reconcileSelection(
        resolved.surface,
        currencyRef.current,
        railRef.current,
        stepRef.current === 'review',
      );
      const paused = stepRef.current === 'review' && !next.reviewing && !flag;
      currencyRef.current = next.currency;
      railRef.current = next.railId;
      setCurrency(next.currency);
      setRailId(next.railId);
      if (stepRef.current === 'review' && !next.reviewing) {
        stepRef.current = 'details';
        setStep('details');
        paymentKey.current = crypto.randomUUID();
        if (paused) {
          setNotice('European payments are paused. GBP card and bank payments are still available.');
        }
      }
    }
    async function poll() {
      const version = revision.current;
      const flag = await readEuFlag(room);
      if (closed || generation !== epoch.current) return;
      try {
        if (!mutating.current) {
          const [raw, catalog] = await Promise.all([
            request(room, '/state'),
            request(room, '/catalog'),
          ]);
          if (
            !closed &&
            generation === epoch.current &&
            version === revision.current &&
            !mutating.current
          ) {
            setState(bankState(raw));
            setRecipients(catalog.recipients);
            setConnected(true);
            setError('');
            const providers = Array.isArray(catalog.providers)
              ? (catalog.providers as CatalogProvider[])
              : null;
            applyFlag(flag, providers);
          }
        }
      } catch (e) {
        if (!closed && generation === epoch.current) {
          setConnected(false);
          setError(e instanceof Error ? e.message : 'API unavailable');
          if (!mutating.current) applyFlag(flag, null);
        }
      } finally {
        if (!closed) timer = setTimeout(poll, 2000);
      }
    }
    void poll();
    return () => {
      closed = true;
      clearTimeout(timer);
    };
  }, [room]);
  async function mutate(path: string, httpMethod: string, body?: unknown, key?: string) {
    if (mutating.current || !connected)
      throw new Error('Wait for API connection before submitting.');
    const generation = epoch.current;
    mutating.current = true;
    setBusy(true);
    revision.current++;
    try {
      const result = await request(room, path, httpMethod, body, key);
      if (generation !== epoch.current) throw new Error('Room changed');
      if (result.state) setState(bankState(result.state));
      return result;
    } finally {
      revision.current++;
      mutating.current = false;
      setBusy(false);
    }
  }
  function freshPayment() {
    setStep('details');
    setAmount('');
    setNote('');
    setError('');
    setReceipt(null);
    paymentKey.current = crypto.randomUUID();
    setPage('Pay');
  }
  function editPayment() {
    setStep('details');
    setError('');
    paymentKey.current = crypto.randomUUID();
  }
  function review() {
    const value = pence(amount);
    const unit = currency === 'EUR' ? '€' : '£';
    if (value === null) {
      setError(`Enter an amount from ${unit}0.01 to ${unit}10,000 with no more than two decimals.`);
      return;
    }
    if (currency === 'GBP' && (!state || value > state.balance)) {
      setError('Insufficient balance');
      return;
    }
    setError('');
    setStep('review');
  }
  async function confirm() {
    const rail =
      surface.rails.find((item) => item.id === railId) ??
      surface.rails.find((item) => item.currency === currency);
    if (!rail) {
      setError('Payment method unavailable. GBP card and bank payments are still available.');
      setStep('details');
      return;
    }
    if (rail.currency !== 'GBP') {
      setNotice('EUR stays on this device. The shared ledger settles in GBP pence, so no payment was sent.');
      setError('');
      return;
    }
    try {
      setError('');
      const result = await mutate(
        '/payments',
        'POST',
        { recipientId: recipient, amountMinor: pence(amount), method: rail.method, note, scenario },
        paymentKey.current,
      );
      if (result.ok) {
        setReceipt(result.transaction);
        setStep('done');
      } else setError(result.error || 'Payment pending confirmation. Do not create a new payment.');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Payment failed');
    }
  }
  const selected = recipients.find((item) => item.id === recipient);
  const visibleRails = surface.rails.filter((rail) => rail.currency === currency);
  const methodRails = visibleRails.length > 0 ? visibleRails : surface.rails;
  const spent =
    state?.transactions
      .filter((t) => t.status === 'completed' && t.date.startsWith('2026-09'))
      .reduce((n, t) => n + t.amount, 0) || 0;
  return (
    <div className="rehearsal-background">
      <div className="preview-label">
        Mobile web preview · Native Swift / Kotlin sources in this repo
      </div>
      <div className="mobile-shell">
        <header className="mobile-header">
          <a
            href="#"
            onClick={(e) => {
              e.preventDefault();
              setPage('Home');
            }}
          >
            meridian<span>MONEY, IN BALANCE.</span>
          </a>
          <span className="avatar">AM</span>
        </header>
        <div className="connection-bar">
          <span className={connected ? 'status-dot' : 'status-dot offline'} />
          <strong>{connected ? 'Connected API' : 'API unavailable'}</strong>
          <span>{surface.flagEnabled ? 'EU payments on' : 'GBP baseline'}</span>
          <span>{room}</span>
        </div>
        <main>
          {error && (
            <div role="alert" className="error-message">
              {error}
            </div>
          )}
          {notice && (
            <p role="status" className="notice-message">
              {notice}
            </p>
          )}
          {!state ? (
            <section className="mobile-card">
              <h1>Connecting your money.</h1>
              <p>
                Start meridian-api to load this rehearsal room. No local payment fallback is used.
              </p>
            </section>
          ) : (
            <>
              {page === 'Home' && (
                <>
                  <div className="mobile-title">
                    <span>FRIDAY, 18 SEPTEMBER 2026</span>
                    <h1>
                      Your everyday,
                      <br />
                      balanced.
                    </h1>
                    <p>A clearer view of what matters, Alex.</p>
                  </div>
                  <section className="mobile-balance">
                    <span>Everyday account · GBP</span>
                    <small>Available balance</small>
                    <strong data-testid="mobile-balance">{money(state.balance)}</strong>
                    <button onClick={freshPayment}>↗ Make a payment</button>
                  </section>
                  <section className="mobile-card">
                    <h2>September in balance</h2>
                    <strong className="spending-amount">{money(spent)}</strong>
                    <p>of {money(state.budgets.reduce((sum, b) => sum + b.limit, 0))} planned</p>
                    {state.budgets.slice(0, 3).map((b) => {
                      const used = state.transactions
                        .filter(
                          (t) =>
                            t.category === b.category &&
                            t.status === 'completed' &&
                            t.date.startsWith('2026-09'),
                        )
                        .reduce((sum, t) => sum + t.amount, 0);
                      return (
                        <div className="mini-budget" key={b.category}>
                          <span>{b.category}</span>
                          <span>
                            {money(used)} / {money(b.limit)}
                          </span>
                          <progress
                            value={Math.min(used, b.limit)}
                            max={b.limit}
                            aria-label={b.category + ' budget'}
                          />
                        </div>
                      );
                    })}
                  </section>
                  <section className="mobile-card">
                    <h2>Recent activity</h2>
                    <History items={[...state.transactions].reverse().slice(0, 3)} />
                  </section>
                </>
              )}
              {page === 'Pay' && (
                <section className="mobile-card">
                  <h1>{step === 'done' ? 'Taken care of.' : 'Make a payment'}</h1>
                  <p>
                    {surface.flagEnabled
                      ? 'EU payments are on for this cohort. The shared ledger still settles in GBP.'
                      : 'GBP card and bank payments. Fictional money.'}
                  </p>
                  {step === 'details' && (
                    <form
                      onSubmit={(e) => {
                        e.preventDefault();
                        review();
                      }}
                    >
                      <label htmlFor="mobile-recipient">Recipient</label>
                      <select
                        id="mobile-recipient"
                        value={recipient}
                        onChange={(e) => setRecipient(e.target.value)}
                      >
                        {recipients.map((item) => (
                          <option key={item.id} value={item.id}>
                            {item.name}
                          </option>
                        ))}
                      </select>
                      {surface.currencies.includes('EUR') && (
                        <fieldset>
                          <legend>Currency</legend>
                          {(['GBP', 'EUR'] as const).map((code) => (
                            <label
                              className={'mobile-method ' + (currency === code ? 'selected' : '')}
                              key={code}
                            >
                              <input
                                type="radio"
                                name="currency"
                                checked={currency === code}
                                onChange={() => {
                                  const next = reconcileSelection(surface, code, railId, false);
                                  setCurrency(next.currency);
                                  setRailId(next.railId);
                                }}
                              />
                              <span>{code}</span>
                            </label>
                          ))}
                        </fieldset>
                      )}
                      <label htmlFor="mobile-amount">Amount ({currency})</label>
                      <input
                        id="mobile-amount"
                        inputMode="decimal"
                        value={amount}
                        maxLength={12}
                        onChange={(e) => setAmount(e.target.value)}
                        placeholder="0.00"
                      />
                      <label htmlFor="mobile-note">Reference</label>
                      <input
                        id="mobile-note"
                        value={note}
                        maxLength={200}
                        onChange={(e) => setNote(e.target.value)}
                        placeholder="What’s it for?"
                      />
                      <fieldset>
                        <legend>Payment method</legend>
                        {methodRails.map((rail) => {
                          const copy = railCopy(rail.label);
                          return (
                            <label
                              className={'mobile-method ' + (railId === rail.id ? 'selected' : '')}
                              key={rail.id}
                            >
                              <input
                                type="radio"
                                name="method"
                                checked={railId === rail.id}
                                onChange={() => setRailId(rail.id)}
                              />
                              <span>
                                {copy.title}
                                <small>{copy.detail}</small>
                              </span>
                            </label>
                          );
                        })}
                      </fieldset>
                      <button className="primary" disabled={!connected || busy} type="submit">
                        Review payment
                      </button>
                    </form>
                  )}
                  {step === 'review' && (
                    <>
                      <div className="mobile-review">
                        <span>To {selected?.name}</span>
                        <strong>{formatMinor(pence(amount) || 0, currency)}</strong>
                        <p>
                          {surface.rails.find((rail) => rail.id === railId)?.label} ·{' '}
                          {note || 'No reference'}
                        </p>
                      </div>
                      <button className="primary" onClick={confirm} disabled={busy || !connected}>
                        {busy ? 'Confirming…' : 'Confirm payment'}
                      </button>
                      <button className="secondary" disabled={busy} onClick={editPayment}>
                        Back to details
                      </button>
                    </>
                  )}
                  {step === 'done' && receipt && (
                    <div className="mobile-success">
                      <span>✓</span>
                      <h2>Demo payment complete</h2>
                      <p>
                        {money(receipt.amount)} to {receipt.name}
                      </p>
                      <code>{receipt.reference}</code>
                      <p>Your web view will update automatically.</p>
                      <button className="primary" onClick={() => setPage('Home')}>
                        Back to overview
                      </button>
                      <button className="secondary" onClick={freshPayment}>
                        Another payment
                      </button>
                    </div>
                  )}
                </section>
              )}
              {page === 'History' && (
                <section className="mobile-card">
                  <h1>Activity</h1>
                  <p>Payments across all clients in this room.</p>
                  <History items={[...state.transactions].reverse()} />
                </section>
              )}
              {page === 'Settings' && (
                <section className="mobile-card">
                  <h1>Rehearsal controls</h1>
                  <label htmlFor="mobile-room">Shared room</label>
                  <input
                    id="mobile-room"
                    value={roomInput}
                    onChange={(e) => setRoomInput(e.target.value)}
                  />
                  <button
                    className="secondary"
                    disabled={busy}
                    onClick={() => {
                      if (!/^[A-Za-z0-9_-]{3,64}$/.test(roomInput)) {
                        setError('Room must be 3-64 letters, numbers, hyphens or underscores.');
                        return;
                      }
                      if (roomInput === room) return;
                      epoch.current++;
                      setRoom(roomInput);
                      freshPayment();
                      setPage('Settings');
                    }}
                  >
                    Apply room
                  </button>
                  <label htmlFor="mobile-scenario">Payment scenario</label>
                  <select
                    id="mobile-scenario"
                    value={scenario}
                    onChange={(e) => setScenario(e.target.value)}
                  >
                    <option value="success">Successful payment</option>
                    <option value="declined">Provider declines</option>
                    <option value="unavailable">Provider unavailable</option>
                    <option value="pending">Await signed webhook</option>
                  </select>
                  <h2>Edit monthly budget</h2>
                  <label htmlFor="mobile-category">Category</label>
                  <select
                    id="mobile-category"
                    value={budgetCategory}
                    onChange={(e) => setBudgetCategory(e.target.value as Category)}
                  >
                    {state.budgets.map((b) => (
                      <option key={b.category}>{b.category}</option>
                    ))}
                  </select>
                  <label htmlFor="mobile-limit">Monthly limit (GBP)</label>
                  <input
                    id="mobile-limit"
                    value={budgetAmount}
                    inputMode="decimal"
                    onChange={(e) => setBudgetAmount(e.target.value)}
                  />
                  <button
                    className="primary"
                    disabled={busy || !connected}
                    onClick={async () => {
                      const value = pence(budgetAmount);
                      if (value === null) {
                        setError('Invalid limit');
                        return;
                      }
                      try {
                        await mutate('/budgets', 'PATCH', {
                          category: budgetCategory,
                          limitMinor: value,
                        });
                        setNotice('Budget updated across your room.');
                        setError('');
                      } catch (e) {
                        setError(e instanceof Error ? e.message : 'Update failed');
                      }
                    }}
                  >
                    Save budget
                  </button>
                  <button
                    className="secondary danger"
                    disabled={busy || !connected}
                    onClick={async () => {
                      if (!window.confirm('Reset all clients in this rehearsal room?')) return;
                      try {
                        await mutate('/reset', 'POST');
                        freshPayment();
                        setPage('Home');
                        setNotice('Room reset.');
                      } catch (e) {
                        setError(e instanceof Error ? e.message : 'Reset failed');
                      }
                    }}
                  >
                    Reset shared demo
                  </button>
                  <p className="fine-print">
                    Room IDs isolate fictional data. They are not authentication. Never enter real
                    account or card details.
                  </p>
                </section>
              )}
            </>
          )}
        </main>
        <nav className="mobile-nav" aria-label="Mobile navigation">
          {(['Home', 'Pay', 'History', 'Settings'] as const).map((item) => (
            <button
              key={item}
              aria-current={page === item ? 'page' : undefined}
              onClick={() => {
                setPage(item);
                setNotice('');
              }}
            >
              {item}
            </button>
          ))}
        </nav>
        <footer>Fictional Meridian Bank · GBP simulation</footer>
      </div>
    </div>
  );
}
function railCopy(label: string): { title: string; detail: string } {
  const [title, ...rest] = label.split(' · ');
  return { title, detail: rest.join(' · ') };
}
function History({ items }: { items: Transaction[] }) {
  return (
    <div className="mobile-transactions">
      {items.map((item) => (
        <div key={item.id}>
          <span>
            <strong>{item.name}</strong>
            <small>
              {item.category} · {item.date}
            </small>
          </span>
          <span>
            <strong>−{money(item.amount)}</strong>
            <small>{item.provider}</small>
          </span>
        </div>
      ))}
    </div>
  );
}
