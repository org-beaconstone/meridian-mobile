import { useEffect, useRef, useState } from 'react';
import './index.css';
import {
  createTraceparent,
  probeSessionHealth,
  redact,
  rehearsalTelemetry,
  shouldInjectTraceparent,
} from './domain/telemetry';

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
const providers = [
  { id: 'adyen', name: 'Adyen', method: 'card' as const },
  { id: 'worldpay', name: 'Worldpay', method: 'bank' as const },
];
import { money, parsePence as pence } from './domain/currency';
class RequestError extends Error {
  constructor(
    message: string,
    public code: string,
  ) {
    super(message);
  }
}
type ApiPayload = {
  ok?: boolean;
  error?: string;
  code?: string;
  state?: unknown;
  transaction?: Transaction;
  recipients?: Recipient[];
  providers?: unknown[];
};
async function request(room: string, path: string, method = 'GET', body?: unknown, key?: string): Promise<ApiPayload> {
  const traced = shouldInjectTraceparent(path);
  const traceparent = traced ? createTraceparent() : undefined;
  const started = performance.now();
  let response: Response;
  try {
    response = await fetch('/api/v1' + path, {
      method,
      headers: {
        'Content-Type': 'application/json',
        'X-Rehearsal-Session': room,
        ...(key ? { 'Idempotency-Key': key } : {}),
        ...(traceparent ? { traceparent } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(15000),
    });
  } catch {
    const stage = path.endsWith('/payments') ? 'gateway_roundtrip' : 'network';
    if (path.endsWith('/payments') && traceparent) {
      rehearsalTelemetry.recordGateway({
        traceparent,
        durationMillis: performance.now() - started,
        httpStatus: 0,
        ok: false,
        code: 'NETWORK_ERROR',
        method: paymentMethod(body),
      });
    } else {
      rehearsalTelemetry.recordError('NETWORK_ERROR', stage);
    }
    throw new RequestError(
      'Connection lost. Outcome may be unknown. Retry this same payment after reconnecting.',
      'NETWORK_ERROR',
    );
  }
  const raw = await response.text();
  if (path.endsWith('/catalog')) {
    const parseStarted = performance.now();
    let data: ApiPayload;
    try {
      data = raw ? JSON.parse(raw) : {};
    } catch {
      rehearsalTelemetry.recordError('DECODING_ERROR', 'catalog_parse');
      throw new RequestError('Catalog response could not be read.', 'DECODING_ERROR');
    }
    if (traceparent) {
      rehearsalTelemetry.recordCatalogParse(
        traceparent,
        performance.now() - parseStarted,
        Array.isArray(data.recipients) ? data.recipients.length : 0,
        Array.isArray(data.providers) ? data.providers.length : 0,
      );
    }
    if (!response.ok) {
      throw new RequestError(redact(data.error || `HTTP ${response.status}`), data.code || 'HTTP_ERROR');
    }
    return data;
  }
  let data: ApiPayload;
  try {
    data = raw ? JSON.parse(raw) : {};
  } catch {
    data = {};
  }
  if (path.endsWith('/payments') && traceparent) {
    rehearsalTelemetry.recordGateway({
      traceparent,
      durationMillis: performance.now() - started,
      httpStatus: response.status,
      ok: response.ok && data.ok !== false,
      code: data.code || (response.ok ? undefined : 'HTTP_ERROR'),
      message: data.error,
      method: paymentMethod(body),
    });
  }
  if (!response.ok)
    throw new RequestError(redact(data.error || `HTTP ${response.status}`), data.code || 'HTTP_ERROR');
  return data;
}
function paymentMethod(body: unknown): string | undefined {
  if (!body || typeof body !== 'object' || !('method' in body)) return undefined;
  const method = (body as { method?: unknown }).method;
  return method === 'card' || method === 'bank' ? method : undefined;
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
  const [corridor, setCorridor] = useState('unknown');
  const [page, setPage] = useState<'Home' | 'Pay' | 'History' | 'Settings'>('Home');
  const [recipient, setRecipient] = useState('northline-studio');
  const [amount, setAmount] = useState('');
  const [note, setNote] = useState('');
  const [method, setMethod] = useState<Method>('card');
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
    rehearsalTelemetry.reset();
    setCorridor('unknown');
    setState(null);
    setConnected(false);
    setError('');
    async function poll() {
      const version = revision.current;
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
            setRecipients(catalog.recipients ?? []);
            setConnected(true);
          }
        }
      } catch (e) {
        if (!closed && generation === epoch.current) {
          setConnected(false);
          setError(e instanceof Error ? redact(e.message) : 'API unavailable');
        }
      }
      try {
        const nextCorridor = await probeSessionHealth(room);
        if (!closed && generation === epoch.current) setCorridor(nextCorridor);
      } catch {
        if (!closed && generation === epoch.current) setCorridor('unreachable');
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
    if (value === null) {
      setError('Enter an amount from £0.01 to £10,000 with no more than two decimals.');
      return;
    }
    if (!state || value > state.balance) {
      setError('Insufficient balance');
      return;
    }
    setError('');
    setStep('review');
  }
  async function confirm() {
    const biometric = rehearsalTelemetry.resolveLocalBiometric(method);
    if (!biometric.accepted) {
      setError(
        biometric.fallback
          ? 'Local biometric check could not finish. Retry this same payment.'
          : 'Local biometric check was declined. The payment key is unchanged.',
      );
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
        setReceipt(result.transaction ?? null);
        setStep('done');
      } else if (String(result.code || '').toUpperCase().includes('SCA')) {
        setError('SCA challenge needs another attempt on the same provider. The payment key is unchanged.');
      } else setError(redact(result.error || 'Payment pending confirmation. Do not create a new payment.'));
    } catch (e) {
      if (e instanceof RequestError && e.code.toUpperCase().includes('SCA')) {
        setError('SCA challenge needs another attempt on the same provider. The payment key is unchanged.');
      } else setError(e instanceof Error ? redact(e.message) : 'Payment failed');
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
          <span data-testid="corridor-state">Corridor {corridor}</span>
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
                      <fieldset>
                        <legend>Payment method</legend>
                        {providers.map((provider) => (
                          <label
                            className={
                              'mobile-method ' + (method === provider.method ? 'selected' : '')
                            }
                            key={provider.id}
                          >
                            <input
                              type="radio"
                              name="method"
                              checked={method === provider.method}
                              onChange={() => setMethod(provider.method)}
                            />
                            <span>
                              {provider.method === 'card' ? 'Debit card' : 'Bank payment'}
                              <small>{provider.name} simulation</small>
                            </span>
                          </label>
                        ))}
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
                        <strong>{money(pence(amount) || 0)}</strong>
                        <p>
                          {providers.find((p) => p.method === method)?.name} ·{' '}
                          {note || 'No reference'}
                        </p>
                        <p>Local biometric check runs on this device before the payment is sent.</p>
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
                    account or card details. This browser companion redacts card numbers and IBANs
                    from its telemetry.
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
