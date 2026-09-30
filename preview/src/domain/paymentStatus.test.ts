import { describe, expect, it } from 'vitest';
import {
  applying,
  backoffMillis,
  classifyIntentStatus,
  latestRecoverable,
  loadSnapshot,
  makeReceipt,
  paymentIntentPath,
  phaseFromPaymentResult,
  pollPaymentIntent,
  presentationPhase,
  recoveryAction,
  recoveryFeedback,
  removeSnapshot,
  saveSnapshot,
  type IntentSnapshot,
  type PaymentIntent,
} from './paymentStatus';

function snapshot(phase: IntentSnapshot['phase'], intentId: string | null): IntentSnapshot {
  return {
    intentId,
    sessionId: 'room-1',
    baseURL: '',
    idempotencyKey: '11111111-1111-4111-8111-111111111111',
    recipientId: 'northline-studio',
    recipientName: 'Northline Studio',
    amountMinor: 1500,
    method: 'card',
    note: 'Materials',
    phase,
    supportReference: null,
    transaction: null,
    provider: 'adyen',
    detail: null,
    updatedAt: '2026-09-18T12:00:00.000Z',
  };
}

describe('authoritative status polling', () => {
  it('keeps jittered backoff inside the cap', () => {
    for (let attempt = 0; attempt < 12; attempt += 1) {
      for (const unit of [0, 0.25, 0.5, 1]) {
        const delay = backoffMillis(attempt, unit);
        expect(delay).toBeLessThanOrEqual(4000);
        expect(delay).toBeGreaterThan(0);
      }
    }
    expect(backoffMillis(0, 0)).toBe(250);
    expect(backoffMillis(0, 1)).toBe(500);
    expect(backoffMillis(3, 1)).toBe(4000);
    expect(backoffMillis(10, 1)).toBe(4000);
    expect(backoffMillis(2, 0)).toBeLessThan(backoffMillis(2, 1));
  });

  it('polls processing, pending, and unknown, then stops on decline or success', async () => {
    let calls = 0;
    const declined = await pollPaymentIntent({
      intentId: 'pi-1',
      fetchIntent: async () => ({ ...intent('declined'), id: 'pi-1' }),
      sleep: async () => {
        throw new Error('decline must not wait for another lookup');
      },
      randomUnit: () => 1,
    });
    expect(declined.phase).toBe('declined');
    expect(declined.attempts).toBe(1);

    const script = ['processing', 'pending', 'mystery', 'succeeded'];
    const sleeps: number[] = [];
    const done = await pollPaymentIntent({
      intentId: 'pi-2',
      fetchIntent: async (id) => {
        calls += 1;
        expect(id).toBe('pi-2');
        return { ...intent(script.shift() || 'unknown'), id, supportReference: 'SUP-140' };
      },
      sleep: async (ms) => {
        sleeps.push(ms);
      },
      randomUnit: () => 0,
      maxElapsedMs: 60_000,
    });
    expect(done.phase).toBe('succeeded');
    expect(calls).toBe(4);
    expect(sleeps.length).toBe(3);
    expect(sleeps.every((ms) => ms <= 4000)).toBe(true);
  });

  it('does not start another lookup after the elapsed budget', async () => {
    let calls = 0;
    const result = await pollPaymentIntent({
      intentId: 'pi-3',
      fetchIntent: async () => {
        calls += 1;
        return intent('processing');
      },
      sleep: async () => {
        throw new Error('elapsed budget should stop before sleeping');
      },
      maxElapsedMs: 0,
    });
    expect(result.phase).toBe('processing');
    expect(calls).toBe(1);
  });

  it('resumes status checks from a stored snapshot and holds a decline', () => {
    localStorage.clear();
    expect(recoveryAction(snapshot('processing', 'pi-open'))).toEqual({ kind: 'poll', intentId: 'pi-open' });
    expect(recoveryAction(snapshot('pending', 'pi-pending'))).toEqual({ kind: 'poll', intentId: 'pi-pending' });
    expect(recoveryAction(snapshot('unknown', 'pi-unknown'))).toEqual({ kind: 'poll', intentId: 'pi-unknown' });
    expect(recoveryAction(snapshot('declined', 'pi-no'))).toEqual({ kind: 'showDecline' });
    expect(recoveryAction(snapshot('unknown', null))).toEqual({ kind: 'holdUnknown' });
    expect(recoveryFeedback('declined')).toContain('will not be submitted again');
    saveSnapshot({ ...snapshot('declined', 'pi-old'), sessionId: 'room-a', updatedAt: '2026-09-18T10:00:00.000Z' });
    saveSnapshot({ ...snapshot('pending', 'pi-new'), sessionId: 'room-b', updatedAt: '2026-09-18T11:00:00.000Z' });
    expect(latestRecoverable()?.intentId).toBe('pi-new');
    expect(loadSnapshot('room-b')?.phase).toBe('pending');
    removeSnapshot('room-b');
    expect(latestRecoverable()?.intentId).toBe('pi-old');
    expect(recoveryAction(loadSnapshot('room-a')!)).toEqual({ kind: 'showDecline' });
  });

  it('builds a receipt with recipient, amount, and support reference', () => {
    const receipt = makeReceipt(snapshot('succeeded', 'pi-1'), {
      ...intent('succeeded'),
      recipientName: 'Northline Studio',
      amountMinor: 2599,
      supportReference: 'SUP-140-7781',
      note: 'Materials',
    });
    expect(receipt.recipientName).toBe('Northline Studio');
    expect(receipt.amountMinor).toBe(2599);
    expect(receipt.supportReference).toBe('SUP-140-7781');
    expect(applying({ phase: 'succeeded', intent: intent('succeeded'), attempts: 1 }, snapshot('processing', 'pi-1')).phase).toBe(
      'succeeded',
    );
    expect(presentationPhase({ ...intent('succeeded'), currency: 'EUR' })).toBe('unknown');
    expect(classifyIntentStatus('PAYMENT_DECLINED')).toBe('declined');
    expect(phaseFromPaymentResult({ ok: false, code: 'PAYMENT_PENDING' })).toBe('pending');
    expect(paymentIntentPath('pi_1')).toBe('/api/v2/payment-intents/pi_1');
  });
});

function intent(status: string): PaymentIntent {
  return {
    id: 'pi-1',
    status,
    amountMinor: 1500,
    currency: 'GBP',
    recipientId: 'northline-studio',
    recipientName: 'Northline Studio',
    method: 'card',
    provider: 'adyen',
    note: 'Materials',
    supportReference: 'SUP-140-7781',
    transaction: {
      id: 'pi-1',
      name: 'Northline Studio',
      amount: 1500,
      date: '2026-09-18',
      category: 'Shopping',
      status: status === 'declined' ? 'declined' : 'completed',
      provider: 'adyen',
      reference: 'SUP-140-7781',
      method: 'card',
      note: 'Materials',
      recipientId: 'northline-studio',
    },
    error: null,
    code: null,
  };
}
