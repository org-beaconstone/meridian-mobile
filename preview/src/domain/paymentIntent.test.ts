import { describe, expect, it } from 'vitest';
import {
  classifyPaymentIntent,
  isQuoteExpired,
  localizedQuoteExpiry,
  localizedRecipientName,
  preparePaymentIntent,
  resolvePaymentIntentsURL,
  sha256Hex,
} from './paymentIntent';

const goldenIntentBody =
  '{"amountMinor":2599,"bank":"Adyen","consentAccepted":true,"consentSummary":"I authorise Meridian to submit this GBP payment to the named recipient. This rehearsal does not move real money or contact Adyen or Worldpay.","currency":"GBP","feeMinor":39,"localReference":"INV-1042","method":"card","provider":"adyen","quoteExpiresAt":"2026-09-18T12:01:00Z","quoteId":"quote-fixed","recipientId":"northline-studio","recipientName":"Northline Studio"}';

const fixed = {
  recipientId: 'northline-studio',
  recipientName: 'Northline Studio',
  recipientDetail: 'Design tools & materials',
  amountInput: '25.99',
  localReference: 'INV-1042',
  method: 'card' as const,
  idempotencyKey: '11111111-1111-4111-8111-111111111111',
  quoteId: 'quote-fixed',
  quoteExpiresAt: '2026-09-18T12:01:00Z',
};

function succeeded(intentId: string) {
  return { statusCode: 200, body: { ok: true, status: 'succeeded', intentId } };
}

describe('payment intent confirmation', () => {
  it('locks a localized review, idempotency key, and payload hash', () => {
    const attempt = preparePaymentIntent(fixed);
    expect(sha256Hex('')).toBe('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    expect(sha256Hex('abc')).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(attempt.canonicalBody).toBe(goldenIntentBody);
    expect(attempt.payloadHash).toBe('c04ec489e9f4ddb99b509f0e493f2f5cd278b93935d65af809d29d28b4a14ef0');
    expect(attempt.review).toMatchObject({
      recipientName: 'Northline Studio',
      amountLabel: '£25.99',
      feeLabel: '£0.39',
      methodLabel: 'Debit card',
      bank: 'Adyen',
      expiryLabel: '18 Sep 2026, 12:01 UTC',
    });
    expect(localizedQuoteExpiry('2026-09-18T12:01:00Z')).toBe('18 Sep 2026, 12:01 UTC');
    const first = preparePaymentIntent({ ...fixed, quoteId: 'quote-one', idempotencyKey: undefined });
    const second = preparePaymentIntent({ ...fixed, quoteId: 'quote-two', idempotencyKey: undefined });
    expect(first.idempotencyKey).not.toBe(second.idempotencyKey);
    expect(first.payloadHash).not.toBe(second.payloadHash);
    expect(first.idempotencyKey).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    );
  });

  it('rejects a bad local reference or amount before any submit', async () => {
    expect(() => preparePaymentIntent({ ...fixed, localReference: '  ' })).toThrow(/reference/i);
    expect(() => preparePaymentIntent({ ...fixed, amountInput: '10.501' })).toThrow(/decimal/i);
    const bank = preparePaymentIntent({
      ...fixed,
      recipientName: 'Cafe\u0301',
      method: 'bank',
      amountInput: '8',
      localReference: '  REF-8  ',
      idempotencyKey: 'bank-key',
      quoteId: 'quote-bank',
    });
    expect(bank.review.bank).toBe('Worldpay');
    expect(bank.review.feeLabel).toBe('£0.00');
    expect(bank.review.localReference).toBe('REF-8');
    expect(localizedRecipientName('Cafe\u0301')).toBe('Café');
    expect(bank.review.recipientName).toBe('Café');
    expect(resolvePaymentIntentsURL('http://127.0.0.1:8080/api/v1/')).toBe(
      'http://127.0.0.1:8080/api/v2/payment-intents',
    );
    const hits = { count: 0 };
    await expect(bank.submit(new Date(0), false, async () => {
      hits.count += 1;
      return succeeded('no');
    })).rejects.toThrow(/Consent/);
    expect(hits.count).toBe(0);
    expect(isQuoteExpired(bank.quoteExpiresAt, new Date('2026-09-18T12:01:00Z'))).toBe(true);
  });

  it('keeps one intent across a rapid tap, decline, and action required', async () => {
    const attempt = preparePaymentIntent(fixed);
    let release: () => void = () => {};
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    const hits = { count: 0 };
    const now = new Date(0);
    const first = attempt.submit(now, true, async () => {
      hits.count += 1;
      await gate;
      return succeeded('pi_ok');
    });
    await expect(attempt.submit(now, true, async () => {
      hits.count += 1;
      return succeeded('pi_new');
    })).rejects.toThrow(/already being submitted/);
    release();
    await expect(first).resolves.toMatchObject({ intentId: 'pi_ok', disposition: 'succeeded' });
    await expect(attempt.submit(new Date(), true, async () => succeeded('pi_new'))).resolves.toMatchObject({
      intentId: 'pi_ok',
    });
    expect(hits.count).toBe(1);

    const declined = preparePaymentIntent(fixed);
    const declinedHits = { count: 0 };
    const declinedResult = await declined.submit(now, true, async () => {
      declinedHits.count += 1;
      return {
        statusCode: 422,
        body: { ok: false, status: 'declined', intentId: 'pi_decline', code: 'DECLINED', error: 'The payment was declined' },
      };
    });
    const declinedAgain = await declined.submit(now, true, async () => {
      declinedHits.count += 1;
      return succeeded('pi_other');
    });
    expect(declinedResult.disposition).toBe('declined');
    expect(declinedResult.message).toMatch(/stays closed/);
    expect(declinedAgain.intentId).toBe('pi_decline');
    expect(declinedHits.count).toBe(1);

    const action = preparePaymentIntent(fixed);
    const actionHits = { count: 0 };
    const actionResult = await action.submit(now, true, async () => {
      actionHits.count += 1;
      return {
        statusCode: 202,
        body: {
          ok: false,
          status: 'action_required',
          intent_id: 'pi_action',
          code: 'ACTION_REQUIRED',
          error: 'Additional customer action is required',
        },
      };
    });
    const actionAgain = await action.submit(now, true, async () => {
      actionHits.count += 1;
      return succeeded('pi_other');
    });
    expect(classifyPaymentIntent(202, { status: 'action-required' })).toBe('actionRequired');
    expect(actionResult.disposition).toBe('actionRequired');
    expect(actionResult.intentId).toBe('pi_action');
    expect(actionResult.message).toMatch(/not recreated/);
    expect(actionAgain.intentId).toBe('pi_action');
    expect(actionHits.count).toBe(1);
  });

  it('retries an uncertain bank payment with the same key and hash', async () => {
    const attempt = preparePaymentIntent({
      ...fixed,
      method: 'bank',
      amountInput: '12',
      localReference: 'REF-12',
      idempotencyKey: 'bank-retry-key',
      quoteId: 'quote-bank-retry',
      quoteExpiresAt: '2026-09-18T12:05:00Z',
    });
    const hits: string[] = [];
    await expect(
      attempt.submit(new Date(0), true, async () => {
        hits.push('fail');
        throw new Error('gateway timeout');
      }),
    ).rejects.toThrow(/gateway timeout/);
    const retried = await attempt.submit(new Date('2030-01-01T00:00:00Z'), true, async (body, key, hash) => {
      hits.push(key);
      expect(hash).toBe(attempt.payloadHash);
      expect(body).toContain('"provider":"worldpay"');
      expect(body).toContain('"method":"bank"');
      return succeeded('pi_bank');
    });
    expect(hits).toEqual(['fail', 'bank-retry-key']);
    expect(retried.intentId).toBe('pi_bank');
  });
});
