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
const providers = [
  { id: 'adyen', name: 'Adyen', method: 'card' as const },
  { id: 'worldpay', name: 'Worldpay', method: 'bank' as const },
];
import { money, parsePence as pence } from './domain/currency';
import {
  BIOMETRIC_PROMPT,
  FAILURE_MESSAGE,
  afterBiometric,
  afterPasscode,
  interpretSca,
  paymentBody,
  sessionToken,
  showsPasscode,
  startSession,
  type PaymentDraft,
  type ScaSession,
} from './domain/sca';
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
  return { ...data, httpStatus: response.status as number };
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
  const [step, setStep] = useState<'details' | 'review' | 'sca' | 'done'>('details');
  const [sca, setSca] = useState<ScaSession | null>(null);
  const [passcode, setPasscode] = useState('');
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
            setRecipients(catalog.recipients);
            setConnected(true);
          }
        }
      } catch (e) {
        if (!closed && generation === epoch.current) {
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
    setSca(null);
    setPasscode('');
    paymentKey.current = crypto.randomUUID();
    setPage('Pay');
  }
  function editPayment() {
    setStep('details');
    setError('');
    setSca(null);
    setPasscode('');
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
  function currentDraft(): PaymentDraft | null {
    const amountMinor = pence(amount);
    if (amountMinor === null) return null;
    return {
      recipientId: recipient,
      amountMinor,
      method,
      note,
      scenario,
      idempotencyKey: paymentKey.current,
    };
  }
  async function settle(draft: PaymentDraft, token?: string | null) {
    const result = await mutate(
      '/payments',
      'POST',
      paymentBody(draft, token),
      draft.idempotencyKey,
    );
    const intercept = interpretSca(result.httpStatus, result);
    if (intercept.kind === 'required' && !token) {
      const session = afterBiometric(startSession(draft, intercept.challenge), 'unavailable');
      setSca(session);
      setStep('sca');
      setError('');
      return;
    }
    if (
      intercept.kind === 'expired' ||
      intercept.kind === 'invalid' ||
      (intercept.kind === 'required' && token)
    ) {
      setError(FAILURE_MESSAGE);
      return;
    }
    if (result.ok) {
      setReceipt(result.transaction);
      setSca(null);
      setPasscode('');
      setStep('done');
      setError('');
    } else setError(result.error || 'Payment pending confirmation. Do not create a new payment.');
  }
  async function confirm() {
    const draft = currentDraft();
    if (!draft) {
      setError('Enter an amount from £0.01 to £10,000 with no more than two decimals.');
      return;
    }
    try {
      setError('');
      await settle(draft);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Payment failed');
    }
  }
  async function verifyPasscode() {
    if (!sca) return;
    const next = afterPasscode(sca, passcode);
    setPasscode('');
    setSca(next);
    const token = sessionToken(next);
    if (!token) {
      setError(next.message || FAILURE_MESSAGE);
      return;
    }
    await sendVerified(next.draft, token);
  }
  async function sendVerified(draft: PaymentDraft, token: string) {
    try {
      setError('');
      await settle(draft, token);
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
                      </div>
                      <button className="primary" onClick={confirm} disabled={busy || !connected}>
                        {busy ? 'Confirming…' : 'Confirm payment'}
                      </button>
                      <button className="secondary" disabled={busy} onClick={editPayment}>
                        Back to details
                      </button>
                    </>
                  )}
                  {step === 'sca' && sca && (
                    <div className="sca-panel" data-testid="sca-challenge">
                      <p className="sca-label">
                        Browser companion stand-in. This is not Face ID, Touch ID, or Android
                        BiometricPrompt.
                      </p>
                      <h2>{BIOMETRIC_PROMPT}</h2>
                      <div className="mobile-review">
                        <span data-testid="sca-recipient">To {selected?.name}</span>
                        <strong data-testid="sca-amount">{money(sca.draft.amountMinor)}</strong>
                        <p>
                          {providers.find((p) => p.method === sca.draft.method)?.name} ·{' '}
                          {sca.draft.note || 'No reference'}
                        </p>
                      </div>
                      {sessionToken(sca) ? (
                        <button
                          className="primary"
                          type="button"
                          disabled={busy || !connected}
                          onClick={() => {
                            const token = sessionToken(sca);
                            if (token) void sendVerified(sca.draft, token);
                          }}
                        >
                          {busy ? 'Confirming…' : 'Retry payment'}
                        </button>
                      ) : (
                        showsPasscode(sca) && (
                          <form
                            onSubmit={(event) => {
                              event.preventDefault();
                              void verifyPasscode();
                            }}
                          >
                            <p>
                              In-app passcode. It stays in this browser companion and is not sent to the
                              API.
                            </p>
                            <label htmlFor="mobile-passcode">Security passcode</label>
                            <input
                              id="mobile-passcode"
                              type="password"
                              inputMode="numeric"
                              autoComplete="off"
                              value={passcode}
                              onChange={(event) => setPasscode(event.target.value)}
                            />
                            <button className="primary" type="submit" disabled={busy || !connected}>
                              {busy ? 'Confirming…' : 'Verify passcode'}
                            </button>
                          </form>
                        )
                      )}
                      <button className="secondary" disabled={busy} onClick={editPayment}>
                        Back to details
                      </button>
                    </div>
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
