import { useState } from 'react';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, describe, expect, it } from 'vitest';
import { ScaSheet } from './ScaSheet';
import { SCA_REHEARSAL_PIN, SCA_REJECTION_BANNER, createScaEngine, type ScaEngine } from './domain/sca';

const binding = {
  recipientId: 'northline-studio',
  amountMinor: 1050,
  method: 'card' as const,
  idempotencyKey: 'pay-key-1',
};

function Harness() {
  const [now, setNow] = useState(1_700_000_000);
  const [engine, setEngine] = useState<ScaEngine>(() =>
    createScaEngine(binding, { challengeId: 'challenge-1', nonce: 'nonce-1' }),
  );
  const [done, setDone] = useState(false);
  return (
    <div>
      <button type="button" data-testid="advance" onClick={() => setNow((value) => value + 30)}>
        Advance
      </button>
      <ScaSheet
        engine={engine}
        now={now}
        onChange={setEngine}
        onCancel={() => undefined}
        onVerified={() => setDone(true)}
      />
      <output data-testid="verified">{done ? 'yes' : 'no'}</output>
    </div>
  );
}

const mounts: { root: Root; host: HTMLDivElement }[] = [];

function render() {
  const host = document.createElement('div');
  document.body.appendChild(host);
  const root = createRoot(host);
  act(() => {
    root.render(<Harness />);
  });
  mounts.push({ root, host });
  return host;
}

function click(host: ParentNode, name: string) {
  const button = [...host.querySelectorAll('button')].find((item) => item.textContent === name);
  if (!button) throw new Error(`Missing button ${name}`);
  act(() => {
    button.click();
  });
}

afterEach(() => {
  for (const mount of mounts.splice(0)) {
    act(() => mount.root.unmount());
    mount.host.remove();
  }
});

describe('ScaSheet', () => {
  it('falls back to a masked, rate-limited passcode after biometric rejection', () => {
    const host = render();
    expect(host.querySelector('input')).toBeNull();
    click(host, 'Reject biometrics');
    expect(host.querySelector('[data-testid="sca-banner"]')?.textContent).toBe(SCA_REJECTION_BANNER);
    click(host, '1');
    const dots = host.querySelector('[data-testid="sca-dots"]');
    expect(dots?.textContent).toBe('•○○○○○');
    expect(dots?.textContent).not.toMatch(/\d/u);
    click(host, 'Delete');

    for (let attempt = 0; attempt < 5; attempt += 1) {
      for (const digit of '000000') click(host, digit);
    }
    expect(host.textContent).toContain('Too many attempts');
    const zero = [...host.querySelectorAll('button')].find((item) => item.textContent === '0');
    expect((zero as HTMLButtonElement).disabled).toBe(true);
    click(host, 'Advance');
    for (const digit of SCA_REHEARSAL_PIN) click(host, digit);
    expect(host.querySelector('[data-testid="verified"]')?.textContent).toBe('yes');
    expect(host.querySelector('[data-testid="sca-dots"]')?.textContent ?? '').not.toContain(SCA_REHEARSAL_PIN);
  });
});
