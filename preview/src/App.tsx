import { useEffect, useRef, useState } from 'react';
import './index.css';

type Method = 'card' | 'bank';
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
import { money, parsePence as pence } from './domain/currency';
import {
  paymentMethodBlockMessage,
  paymentMethodSheetModel,
  type CatalogProvider,
} from './domain/paymentMethods';
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
  const [method, setMethod] = useState<Method>('card');
  const [catalogProviders, setCatalogProviders] = useState<CatalogProvider[] | null>(null);
  const [catalogFailed, setCatalogFailed] = useState(false);
  const [methodSheetOpen, setMethodSheetOpen] = useState(false);
  const [step, setStep] = useState<'details' | 'review' | 'done'>('details');
  const [scenario, setScenario] = useState('success');
  const [busy, setBusy] = useState(false);
  const [receipt, setReceipt] = useState<Transaction | null>(null);
  const [budgetCategory, setBudgetCategory] = useState<Category>('Shopping');
  const [budgetAmount, setBudgetAmount] = useState('1000');
  const epoch = useRef(0),
    revision = useRef(0),
    mutating = useRef(false),
    paymentKey = useRef(crypto.randomUUID());
  useEffect(() => {
    const generation = ++epoch.current;
    let closed = false;
    let timer: ReturnType<typeof setTimeout>;
    setState(null);
    setCatalogProviders(null);
    setCatalogFailed(false);
    setMethodSheetOpen(false);
    setConnected(false);
    setError('');
    async function poll() {
      const version = revision.current;
      try {
        if (!mutating.current) {
          let stateOk = false;
          try {
            const raw = await request(room, '/state');
            if (
              !closed &&
              generation === epoch.current &&
              version === revision.current &&
              !mutating.current
            ) {
              setState(bankState(raw));
              setConnected(true);
              stateOk = true;
            }
          } catch (e) {
            if (!closed && generation === epoch.current) {
              setConnected(false);
              setError(e instanceof Error ? e.message : 'API unavailable');
            }
          }
          if (
            !closed &&
            generation === epoch.current &&
            version === revision.current &&
            !mutating.current
          ) {
            const catalog = await request(room, '/catalog');
            if (
              !closed &&
              generation === epoch.current &&
              version === revision.current &&
              !mutating.current
            ) {
              setRecipients(catalog.recipients);
              setCatalogProviders(Array.isArray(catalog.providers) ? catalog.providers : []);
              setCatalogFailed(false);
              if (stateOk) setConnected(true);
            }
          }
        }
      } catch (e) {
        if (!closed && generation === epoch.current) {
          setCatalogFailed(true);
          setConnected(false);
          setError(e instanceof Error ? e.message : 'API unavailable');
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
  const sheetRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!methodSheetOpen) return;
    sheetRef.current?.focus();
    function onKey(event: KeyboardEvent) {
      if (event.key === 'Escape') setMethodSheetOpen(false);
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [methodSheetOpen]);
  const methodSheet =
    catalogFailed && catalogProviders === null
      ? { loading: false, options: [], placeholderCount: 0 }
      : paymentMethodSheetModel(catalogProviders);
  const selectedTitle =
    methodSheet.options.find((item) => item.method === method)?.title ?? 'Payment method';
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
    if (value === null) {
      setError('Enter an amount from £0.01 to £10,000 with no more than two decimals.');
      return;
    }
    if (!state || value > state.balance) {
      setError('Insufficient balance');
      return;
    }
    const blocked = paymentMethodBlockMessage(method, methodSheet);
    if (blocked) {
      setError(blocked);
      return;
    }
    setError('');
    setStep('review');
  }
  async function confirm() {
    const blocked = paymentMethodBlockMessage(method, methodSheet);
    if (blocked) {
      setError(blocked);
      return;
    }
    try {
      setError('');
      const result = await mutate(
        '/payments',
        'POST',
        { recipientId: recipient, amountMinor: pence(amount), method, note, scenario },
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
                  <p>Fictional money. Shared rehearsal account.</p>
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
                      <label htmlFor="mobile-amount">Amount (GBP)</label>
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
                      <button
                        type="button"
                        className="method-opener"
                        data-testid="payment-method-open"
                        onClick={() => setMethodSheetOpen(true)}
                      >
                        <span>Payment method</span>
                        <strong>{selectedTitle}</strong>
                      </button>
                      <button className="primary" disabled={!connected || busy} type="submit">
                        Review payment
                      </button>
                    </form>
                  )}
                  {step === 'review' && (
                    <>
                      <div className="mobile-review">
                        <span>To {selected?.name}</span>
                        <strong>{money(pence(amount) || 0)}</strong>
                        <p>
                          {selectedTitle} ·{' '}
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
        {methodSheetOpen && page === 'Pay' && step === 'details' && (
          <div className="method-sheet-backdrop" onClick={() => setMethodSheetOpen(false)}>
            <div
              className="method-sheet"
              role="dialog"
              aria-modal="true"
              aria-label="Payment method"
              data-testid="payment-method-sheet"
              ref={sheetRef}
              tabIndex={-1}
              onClick={(event) => event.stopPropagation()}
              onKeyDown={(event) => {
                if (event.key === 'Escape') setMethodSheetOpen(false);
              }}
            >
              <div className="method-sheet-handle" aria-hidden="true" />
              <div className="method-sheet-heading">
                <div>
                  <h2>Payment method</h2>
                  <p>GBP · United Kingdom</p>
                </div>
                <button type="button" onClick={() => setMethodSheetOpen(false)}>
                  Done
                </button>
              </div>
              {methodSheet.loading ? (
                <div
                  className="method-skeleton"
                  data-testid="method-skeleton"
                  aria-busy="true"
                  aria-label="Loading payment methods"
                >
                  {Array.from({ length: methodSheet.placeholderCount }, (_, index) => (
                    <div className="skeleton-row" key={index} />
                  ))}
                </div>
              ) : methodSheet.options.length === 0 ? (
                <p className="method-empty">No payment method is available for this corridor.</p>
              ) : (
                <div role="radiogroup" aria-label="Payment method">
                  {methodSheet.options.map((option) => (
                    <label
                      key={option.id}
                      className={
                        'method-option' +
                        (method === option.method && option.selectable ? ' selected' : '') +
                        (option.selectable ? '' : ' disabled')
                      }
                      data-testid={'method-option-' + option.id}
                    >
                      <input
                        type="radio"
                        name="payment-method"
                        checked={method === option.method}
                        disabled={!option.selectable}
                        aria-label={option.accessibilityLabel}
                        aria-describedby={option.helperText ? option.id + '-help' : undefined}
                        onChange={() => {
                          if (!option.selectable) return;
                          setMethod(option.method);
                          setMethodSheetOpen(false);
                        }}
                      />
                      <span>
                        {option.title}
                        {option.helperText && <small id={option.id + '-help'}>{option.helperText}</small>}
                      </span>
                    </label>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
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
