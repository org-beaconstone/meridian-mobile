import { describe, expect, it } from 'vitest';
import { EUROPEAN_SCA_PROMPT, SCA_LATENCY_BUDGET_MS, assessSca, verificationToken } from './sca';

const future = '2099-01-01T00:00:00Z';
const past = '2020-01-01T00:00:00Z';

describe('SCA step-up', () => {
  it('derives a stable local verification token inside the latency budget', () => {
    expect(SCA_LATENCY_BUDGET_MS).toBe(300);
    const started = performance.now();
    const token = verificationToken('cht_european_1');
    expect(token).toBe('sca_v1_7e0e3ab4c6566286');
    expect(performance.now() - started).toBeLessThan(300);
    expect(verificationToken('cht_european_1')).toBe(token);
  });

  it('reads an HTTP 202 challenge and treats the expiry instant as closed', () => {
    const ready = assessSca(
      202,
      {
        code: 'SCA_STEP_UP_REQUIRED',
        challengeToken: 'cht_european_1',
        challengeExpiresAt: future,
      },
      Date.parse('2026-10-04T09:00:00Z'),
    );
    expect(ready).toEqual({
      kind: 'ready',
      challenge: {
        token: 'cht_european_1',
        expiresAtMs: Date.parse(future),
        prompt: EUROPEAN_SCA_PROMPT,
      },
    });
    const expired = assessSca(
      202,
      { code: 'SCA_STEP_UP_REQUIRED', challengeToken: 'cht_european_1', challengeExpiresAt: past },
      Date.parse('2026-10-04T09:00:00Z'),
    );
    expect(expired.kind).toBe('expired');
    const boundary = assessSca(
      202,
      {
        code: 'SCA_STEP_UP_REQUIRED',
        challengeToken: 'cht_european_1',
        challengeExpiresAt: '2026-10-04T09:00:00Z',
      },
      Date.parse('2026-10-04T09:00:00Z'),
    );
    expect(boundary.kind).toBe('expired');
  });

  it('leaves pending payments and malformed challenges alone', () => {
    expect(assessSca(202, { code: 'PAYMENT_PENDING', challengeToken: 'cht_european_1' }).kind).toBe(
      'not-required',
    );
    expect(
      assessSca(200, {
        code: 'SCA_STEP_UP_REQUIRED',
        challengeToken: 'cht_european_1',
        challengeExpiresAt: future,
      }).kind,
    ).toBe('not-required');
    expect(assessSca(202, { code: 'SCA_STEP_UP_REQUIRED' }).kind).toBe('malformed');
    expect(
      assessSca(202, {
        code: 'SCA_STEP_UP_REQUIRED',
        challengeToken: 'cht_european_1',
        challengeExpiresAt: 'tomorrow',
      }).kind,
    ).toBe('malformed');
  });
});
