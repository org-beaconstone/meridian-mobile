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
  isQuoteExpired,
  preparePaymentIntent,
  type PaymentIntentAttempt,
  type PaymentIntentResponseBody,
  type PaymentIntentSubmission,
} from './domain/paymentIntent';
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
async function postPaymentIntent(
  room: string,
  body: string,
  key: string,
  hash: string,
  scenario: string,
) {
  let response: Response;
  try {
    response = await fetch('/api/v2/payment-intents', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Rehearsal-Session': room,
        'Idempotency-Key': key,
        'X-Payload-Hash': hash,
        'X-Rehearsal-Scenario': scenario,
      },
      body,
      signal: AbortSignal.timeout(15000),
    });
  } catch {
    throw new Error(
      'Outcome may be unknown. Retry keeps the same idempotency key and payload hash.',
    );
  }
  const text = await response.text();
  let data: PaymentIntentResponseBody = {};
  if (text) {
    try {
      data = JSON.parse(text) as PaymentIntentResponseBody;
    } catch {
      throw new Error(
        `HTTP ${response.status}. Retry keeps the same idempotency key and payload hash.`,
      );
    }
  }
  const allowed =
    (response.status >= 200 && response.status < 300) ||
    response.status === 400 ||
    response.status === 409 ||
    response.status === 422 ||
    response.status === 503;
  if (!allowed) {
    throw new Error(
      data.error ||
        `HTTP ${response.status}. Retry keeps the same idempotency key and payload hash.`,
    );
  }
  return { statusCode: response.status, body: data };
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
  const [step, setStep] = useState<'details' | 'review' | 'done'>('details');
  const [scenario, setScenario] = useState('success');
  const [busy, setBusy] = useState(false);
  const [consent, setConsent] = useState(false);
  const [intentAttempt, setIntentAttempt] = useState<PaymentIntentAttempt | null>(null);
  const [intentOutcome, setIntentOutcome] = useState<PaymentIntentSubmission | null>(null);
  const [intentLocked, setIntentLocked] = useState(false);
  const [nowTick, setNowTick] = useState(() => Date.now());
  const [receipt, setReceipt] = useState<Transaction | null>(null);
  const [budgetCategory, setBudgetCategory] = useState<Category>('Shopping');
  const [budgetAmount, setBudgetAmount] = useState('1000');
  const epoch = useRef(0),
    revision = useRef(0),
    mutating = useRef(false),
    submittingRef = useRef(false);
  useEffect(() => {
    if (step !== 'review') return;
    const timer = setInterval(() => setNowTick(Date.now()), 1000);
    return () => clearInterval(timer);
  }, [step]);
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
    setConsent(false);
    setIntentAttempt(null);
    setIntentOutcome(null);
    setIntentLocked(false);
    setPage('Pay');
  }
  function editPayment() {
    if (submittingRef.current || intentLocked) return;
    setStep('details');
    setError('');
    setConsent(false);
    setIntentAttempt(null);
    setIntentOutcome(null);
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
    try {
      const person = recipients.find((item) => item.id === recipient);
      const next = preparePaymentIntent({
        recipientId: recipient,
        recipientName: person?.name ?? '',
        recipientDetail: person?.detail ?? '',
        amountInput: amount,
        localReference: note,
        method,
      });
      setIntentAttempt(next);
      setConsent(false);
      setIntentOutcome(null);
      setIntentLocked(false);
      setNowTick(Date.now());
      setError('');
      setStep('review');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Invalid payment');
    }
  }
  function refreshQuote() {
    if (submittingRef.current || intentLocked) return;
    try {
      const person = recipients.find((item) => item.id === recipient);
      const next = preparePaymentIntent({
        recipientId: recipient,
        recipientName: person?.name ?? '',
        recipientDetail: person?.detail ?? '',
        amountInput: amount,
        localReference: note,
        method,
      });
      setIntentAttempt(next);
      setConsent(false);
      setIntentOutcome(null);
      setNowTick(Date.now());
      setError('');
      setNotice('Quote refreshed. Review the new expiry before confirming.');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not refresh quote');
    }
  }
  async function confirm() {
    const current = intentAttempt;
    if (!current || submittingRef.current) {
      if (submittingRef.current) setError('Payment is already being submitted.');
      return;
    }
    if (current.settledSubmission) {
      setIntentOutcome(current.settledSubmission);
      return;
    }
    if (!intentLocked && !consent) {
      setError('Consent is required');
      return;
    }
    if (!intentLocked && isQuoteExpired(current.quoteExpiresAt, new Date(nowTick))) {
      setError('Quote expired. Refresh the quote before confirming.');
      return;
    }
    if (!connected) {
      setError('Wait for API connection before submitting.');
      return;
    }
    submittingRef.current = true;
    setIntentLocked(true);
    setBusy(true);
    setError('');
    try {
      const submission = await current.submit(new Date(nowTick), true, async (body, key, hash) => {
        mutating.current = true;
        revision.current += 1;
        try {
          return await postPaymentIntent(room, body, key, hash, scenario);
        } finally {
          revision.current += 1;
          mutating.current = false;
        }
      });
      setIntentOutcome(submission);
      if (submission.disposition === 'succeeded' && submission.body.state) {
        setReceipt((submission.body.state as State).transactions?.at(-1) ?? null);
        setState(bankState(submission.body.state));
        setNotice(submission.message);
      } else if (submission.disposition === 'succeeded') {
        setNotice(submission.message);
      } else {
        setError(submission.message);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Payment failed');
    } finally {
      submittingRef.current = false;
      setBusy(false);
    }
  }
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
                      <label htmlFor="mobile-note">Local reference</label>
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
                  {step === 'review' && intentAttempt && (
                    <>
                      <dl className="intent-review">
                        <div>
                          <dt>Recipient</dt>
                          <dd data-testid="review-recipient">
                            {intentAttempt.review.recipientName}
                            {intentAttempt.review.recipientDetail && (
                              <small>{intentAttempt.review.recipientDetail}</small>
                            )}
                          </dd>
                        </div>
                        <div>
                          <dt>Amount</dt>
                          <dd data-testid="review-amount">{intentAttempt.review.amountLabel}</dd>
                        </div>
                        <div>
                          <dt>Fees</dt>
                          <dd data-testid="review-fees">{intentAttempt.review.feeLabel}</dd>
                        </div>
                        <div>
                          <dt>Method</dt>
                          <dd data-testid="review-method">{intentAttempt.review.methodLabel}</dd>
                        </div>
                        <div>
                          <dt>Bank</dt>
                          <dd data-testid="review-bank">{intentAttempt.review.bank}</dd>
                        </div>
                        <div>
                          <dt>Quote expiry</dt>
                          <dd data-testid="review-quote-expiry">{intentAttempt.review.expiryLabel}</dd>
                        </div>
                      </dl>
                      <p className="consent-summary" data-testid="review-consent">
                        {intentAttempt.review.consentSummary}
                      </p>
                      <label className="consent-check">
                        <input
                          type="checkbox"
                          checked={consent}
                          disabled={busy || intentLocked}
                          onChange={(e) => setConsent(e.target.checked)}
                        />
                        I agree to this payment
                      </label>
                      <p className="fine-print" data-testid="review-idempotency">
                        Idempotency {intentAttempt.idempotencyKey}
                      </p>
                      <p className="fine-print" data-testid="review-hash">
                        Payload hash {intentAttempt.payloadHash}
                      </p>
                      {intentOutcome?.terminal ? (
                        <div data-testid="intent-outcome">
                          <p>{intentOutcome.message}</p>
                          {intentOutcome.intentId && <code>{intentOutcome.intentId}</code>}
                          <button className="primary" onClick={freshPayment}>
                            New payment
                          </button>
                        </div>
                      ) : !intentLocked && isQuoteExpired(intentAttempt.quoteExpiresAt, new Date(nowTick)) ? (
                        <>
                          <p role="status">This quote has expired.</p>
                          <button
                            className="primary"
                            disabled={busy || intentLocked}
                            onClick={refreshQuote}
                          >
                            Refresh quote
                          </button>
                        </>
                      ) : (
                        <button
                          className="primary"
                          data-testid="confirm-payment"
                          onClick={confirm}
                          disabled={busy || !consent || !connected}
                        >
                          {busy ? 'Confirming…' : intentLocked ? 'Retry payment' : 'Confirm payment'}
                        </button>
                      )}
                      {!intentLocked && !intentOutcome?.terminal && (
                        <button className="secondary" disabled={busy} onClick={editPayment}>
                          Back to details
                        </button>
                      )}
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
