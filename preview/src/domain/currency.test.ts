import { describe, it, expect } from 'vitest';
import { money, parsePence } from './currency';
describe('mobile integer money', () => {
  it.each([
    ['25.99', 2599],
    ['0.01', 1],
    ['10000', 1000000],
    ['10.5', 1050],
    ['0004.20', 420],
  ])('parses %s', (value, expected) => expect(parsePence(String(value))).toBe(expected));
  it.each([
    '',
    '0',
    '-1',
    '+1',
    '1e2',
    '1.001',
    '10000.01',
    'NaN',
    'Infinity',
    '1,000',
    ' 25',
    '25.',
    '99999999999999999999999',
  ])('rejects %s', (value) => expect(parsePence(value)).toBeNull());
  it('formats GBP', () => expect(money(1248050)).toBe('£12,480.50'));
});
