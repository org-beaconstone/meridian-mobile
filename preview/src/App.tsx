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
  applying,
  baselineProvider,
  fetchPaymentIntent,
  loadSnapshot,
  makeReceipt,
  phaseFromPaymentResult,
  pollPaymentIntent,
  providerLabel,
  recoveryAction,
  recoveryFeedback,
  removeSnapshot,
  saveSnapshot,
  type IntentSnapshot,
  type ReceiptTransaction,
} from './domain/paymentStatus';
class RequestError extends Error {
  constructor(
    message: string,
    public code: string,
    public payload?: PaymentResult,
  ) {
    super(message);
  }
}
type PaymentResult = {
  ok?: boolean;
  code?: string | null;
  error?: string | null;
  paymentId?: string | null;
  transaction?: ReceiptTransaction | null;
  state?: State;
};
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
    throw new RequestError(
      data.error || `HTTP ${response.status}`,
      data.code || 'HTTP_ERROR',
      data,
    );
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
  const [step, setStep] = useState<'details' | 'review' | 'checking' | 'declined' | 'done'>('details');
  const [scenario, setScenario] = useState('success');
  const [busy, setBusy] = useState(false);
  const [handoff, setHandoff] = useState<IntentSnapshot | null>(null);
  const [budgetCategory, setBudgetCategory] = useState<Category>('Shopping');
  const [budgetAmount, setBudgetAmount] = useState('1000');
  const epoch = useRef(0),
    revision = useRef(0),
    mutating = useRef(false),
    paymentKey = useRef<string>(crypto.randomUUID()),
    pollGeneration = useRef(0);
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
  useEffect(() => {
    const saved = loadSnapshot(room);
    if (!saved) return;
    let cancelled = false;
    const token = ++pollGeneration.current;
    setHandoff(saved);
    paymentKey.current = saved.idempotencyKey;
    const action = recoveryAction(saved);
    if (action.kind === 'showReceipt') {
      setStep('done');
      setPage('Pay');
      setError('');
      return;
    }
    if (action.kind === 'showDecline') {
      setStep('declined');
      setPage('Pay');
      setError(recoveryFeedback('declined'));
      return;
    }
    if (action.kind === 'holdUnknown') {
      setStep('checking');
      setPage('Pay');
      setError(recoveryFeedback('unknown'));
      return;
    }
    setStep('checking');
    setPage('Pay');
    setError('');
    setBusy(true);
    void (async () => {
      const result = await pollPaymentIntent({
        intentId: action.intentId,
        fetchIntent: (id) => fetchPaymentIntent(room, id),
      });
      if (cancelled || token !== pollGeneration.current) return;
      const next = applying(result, saved);
      saveSnapshot(next);
      setHandoff(next);
      if (result.phase === 'succeeded') {
        setStep('done');
        setError('');
        paymentKey.current = crypto.randomUUID();
      } else if (result.phase === 'declined') {
        setStep('declined');
        setError(recoveryFeedback('declined'));
      } else {
        setStep('checking');
        setError(recoveryFeedback(result.phase));
      }
      setBusy(false);
    })();
    return () => {
      cancelled = true;
      pollGeneration.current += 1;
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
    const saved = loadSnapshot(room);
    const action = saved ? recoveryAction(saved) : null;
    if (saved && (action?.kind === 'poll' || action?.kind === 'holdUnknown')) {
      setHandoff(saved);
      setPage('Pay');
      setStep('checking');
      setError(recoveryFeedback(saved.phase === 'succeeded' ? 'unknown' : saved.phase));
      return;
    }
    removeSnapshot(room);
    setHandoff(null);
    setStep('details');
    setAmount('');
    setNote('');
    setError('');
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
  function remember(snapshot: IntentSnapshot) {
    saveSnapshot(snapshot);
    setHandoff(snapshot);
  }
  function snapshotFrom(
    result: PaymentResult,
    amountMinor: number,
    recipientName: string,
    phase = phaseFromPaymentResult(result),
  ): IntentSnapshot {
    const tx = result.transaction ?? null;
    return {
      intentId: result.paymentId ?? null,
      sessionId: room,
      baseURL: '',
      idempotencyKey: paymentKey.current,
      recipientId: recipient,
      recipientName: tx?.name || recipientName,
      amountMinor: tx?.amount ?? amountMinor,
      method,
      note,
      phase,
      supportReference: tx?.reference ?? null,
      transaction: tx,
      provider: tx?.provider || baselineProvider(method),
      detail: result.error ?? null,
      updatedAt: new Date().toISOString(),
    };
  }
  async function follow(snapshot: IntentSnapshot) {
    if (!snapshot.intentId) {
      setStep('checking');
      setError(recoveryFeedback('unknown'));
      return;
    }
    const token = ++pollGeneration.current;
    setStep('checking');
    setBusy(true);
    setError('');
    try {
      const result = await pollPaymentIntent({
        intentId: snapshot.intentId,
        fetchIntent: (id) => fetchPaymentIntent(snapshot.sessionId, id),
      });
      if (token !== pollGeneration.current) return;
      const next = applying(result, snapshot);
      remember(next);
      if (result.phase === 'succeeded') {
        setStep('done');
        setError('');
        paymentKey.current = crypto.randomUUID();
      } else if (result.phase === 'declined') {
        setStep('declined');
        setError(recoveryFeedback('declined'));
      } else {
        setStep('checking');
        setError(recoveryFeedback(result.phase));
      }
    } finally {
      if (token === pollGeneration.current) setBusy(false);
    }
  }
  function acceptPaymentResult(result: PaymentResult, amountMinor: number, recipientName: string) {
    const snapshot = snapshotFrom(result, amountMinor, recipientName);
    remember(snapshot);
    if (snapshot.phase === 'succeeded') {
      setStep('done');
      setError('');
      paymentKey.current = crypto.randomUUID();
      return;
    }
    if (snapshot.phase === 'declined') {
      setStep('declined');
      setError(recoveryFeedback('declined'));
      return;
    }
    void follow(snapshot);
  }
  async function confirm() {
    const value = pence(amount);
    if (value === null) {
      setError('Enter an amount from £0.01 to £10,000 with no more than two decimals.');
      return;
    }
    const blocked = handoff ? recoveryAction(handoff) : null;
    if (blocked?.kind === 'poll' || blocked?.kind === 'showDecline') return;
    const recipientName = recipients.find((item) => item.id === recipient)?.name ?? recipient;
    try {
      setError('');
      const result = await mutate(
        '/payments',
        'POST',
        { recipientId: recipient, amountMinor: value, method, note, scenario },
        paymentKey.current,
      );
      acceptPaymentResult(result, value, recipientName);
    } catch (e) {
      if (e instanceof RequestError && e.payload) {
        acceptPaymentResult(e.payload, value, recipientName);
        return;
      }
      const snapshot = snapshotFrom(
        { ok: false, code: 'UNKNOWN', error: e instanceof Error ? e.message : 'Payment failed' },
        value,
        recipientName,
        'unknown',
      );
      remember(snapshot);
      setStep('checking');
      setError(recoveryFeedback('unknown'));
    }
  }
  const selected = recipients.find((item) => item.id === recipient);
  const succeededReceipt = handoff?.phase === 'succeeded' ? makeReceipt(handoff) : null;
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
                  <h1>
                    {step === 'done'
                      ? 'Taken care of.'
                      : step === 'declined'
                        ? 'Payment declined'
                        : step === 'checking'
                          ? 'Checking status'
                          : 'Make a payment'}
                  </h1>
                  <p>
                    {step === 'checking'
                      ? 'Browser companion rehearsal. Status is read from the Java API and does not start another payment.'
                      : 'Fictional money. Shared rehearsal account.'}
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
                  {step === 'checking' && (
                    <div data-testid="status-checking">
                      <p>{error || recoveryFeedback(handoff?.phase === 'pending' ? 'pending' : 'processing')}</p>
                      {handoff?.intentId ? (
                        <button
                          className="secondary"
                          disabled={busy}
                          onClick={() => {
                            if (handoff) void follow(handoff);
                          }}
                        >
                          Check status again
                        </button>
                      ) : (
                        <button className="primary" disabled={busy || !connected} onClick={confirm}>
                          Retry this payment
                        </button>
                      )}
                    </div>
                  )}
                  {step === 'declined' && (
                    <div className="decline-panel" data-testid="payment-declined">
                      <h2>Payment declined</h2>
                      <p>{recoveryFeedback('declined')}</p>
                      <button className="secondary" onClick={freshPayment}>
                        New payment
                      </button>
                    </div>
                  )}
                  {step === 'done' && succeededReceipt && (
                    <div className="mobile-success" data-testid="payment-receipt">
                      <span>✓</span>
                      <h2>Payment complete</h2>
                      <p>
                        {money(succeededReceipt.amountMinor)} to {succeededReceipt.recipientName}
                      </p>
                      <div className="receipt-details">
                        <div>
                          <span>Recipient</span>
                          <strong>{succeededReceipt.recipientName}</strong>
                        </div>
                        <div>
                          <span>Amount</span>
                          <strong>{money(succeededReceipt.amountMinor)}</strong>
                        </div>
                        <div>
                          <span>Support reference</span>
                          <strong data-testid="support-reference">
                            {succeededReceipt.supportReference}
                          </strong>
                        </div>
                        {succeededReceipt.transactionId && (
                          <div>
                            <span>Transaction</span>
                            <strong>{succeededReceipt.transactionId}</strong>
                          </div>
                        )}
                        {succeededReceipt.transactionDate && (
                          <div>
                            <span>Date</span>
                            <strong>{succeededReceipt.transactionDate}</strong>
                          </div>
                        )}
                        <div>
                          <span>Method</span>
                          <strong>
                            {succeededReceipt.method === 'bank' ? 'Bank payment' : 'Debit card'}
                          </strong>
                        </div>
                        <div>
                          <span>Provider</span>
                          <strong>{providerLabel(succeededReceipt.provider)}</strong>
                        </div>
                        {succeededReceipt.note && (
                          <div>
                            <span>Details</span>
                            <strong>{succeededReceipt.note}</strong>
                          </div>
                        )}
                      </div>
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
