import { describe, expect, it } from 'vitest';
import {
  backoffDelayMs,
  corridorNotice,
  isGatewayRetryStatus,
  parseSessionHealth,
  runGatewayRetries,
  type SessionHealth,
} from './resilience';

const degradedCard: SessionHealth = {
  status: 'DEGRADED',
  simulation: true,
  corridors: [
    {
      id: 'EU',
      currency: 'EUR',
      status: 'outage',
      rails: [{ method: 'card', provider: 'adyen', status: 'outage' }],
    },
    {
      id: 'GB',
      currency: 'GBP',
      status: 'degraded',
      rails: [
        { method: 'card', provider: 'adyen', status: 'degraded' },
        { method: 'bank', provider: 'unlisted', status: 'healthy' },
        { method: 'bank', provider: 'worldpay', status: 'healthy' },
      ],
    },
  ],
};

describe('browser companion resilience', () => {
  it('backs off only for 502 and 504', () => {
    expect(backoffDelayMs(1)).toBe(200);
    expect(backoffDelayMs(2)).toBe(400);
    expect(backoffDelayMs(3)).toBe(800);
    expect(backoffDelayMs(8)).toBe(1600);
    expect(isGatewayRetryStatus(502)).toBe(true);
    expect(isGatewayRetryStatus(504)).toBe(true);
    expect(isGatewayRetryStatus(503)).toBe(false);
    expect(isGatewayRetryStatus(500)).toBe(false);
  });

  it('prompts the rehearsed bank rail and ignores an unlisted provider', () => {
    expect(corridorNotice(degradedCard, 'card')).toEqual({
      type: 'switch',
      corridorId: 'GB',
      selected: 'card',
      alternate: 'bank',
      reason: 'degraded',
    });
    expect(corridorNotice(degradedCard, 'bank')).toBeNull();
    const parsed = parseSessionHealth({
      status: 'DOWN',
      extra: true,
      corridors: [
        {
          id: 'GB',
          currency: 'GBP',
          status: 'outage',
          rails: [
            { method: 'card', provider: 'adyen', status: 'outage' },
            { method: 'bank', provider: 'worldpay', status: 'degraded' },
            { method: 'card', provider: 'unlisted', status: 'healthy' },
          ],
        },
      ],
    });
    const notice = corridorNotice(parsed, 'card');
    expect(notice?.type).toBe('unavailable');
    if (notice?.type === 'unavailable') expect(notice.message).not.toContain('unlisted');
  });

  it('retries gateway responses with the same attempt function and stops on other failures', async () => {
    const statuses = [502, 504, 200];
    const seen: number[] = [];
    const delays: number[] = [];
    const value = await runGatewayRetries(
      async () => {
        const status = statuses[seen.length] ?? 502;
        seen.push(status);
        if (status === 502 || status === 504) return { type: 'retry', status };
        return { type: 'success', value: 'paid' };
      },
      {
        sleep: async (ms) => {
          delays.push(ms);
        },
        delay: (attempt) => backoffDelayMs(attempt),
      },
    );
    expect(value).toBe('paid');
    expect(seen).toEqual([502, 504, 200]);
    expect(delays).toEqual([200, 400]);

    const calls: string[] = [];
    await expect(
      runGatewayRetries(
        async () => {
          calls.push('once');
          return { type: 'stop', error: new Error('declined') };
        },
        { sleep: async () => Promise.reject(new Error('should not sleep')) },
      ),
    ).rejects.toThrow('declined');
    expect(calls).toEqual(['once']);
  });
});
