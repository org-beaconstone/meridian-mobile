import { describe, expect, it } from 'vitest';
import {
  createStickyNote,
  defaultStickyColourId,
  maxStickyTextLength,
  stickyColour,
  stickyPalette,
} from './stickyNotes';

describe('whiteboard sticky note colour palette', () => {
  it('offers a named palette and starts on yellow', () => {
    expect(stickyPalette.map((colour) => colour.id)).toEqual([
      'yellow',
      'orange',
      'coral',
      'pink',
      'purple',
      'blue',
      'teal',
      'green',
    ]);
    expect(new Set(stickyPalette.map((colour) => colour.id)).size).toBe(stickyPalette.length);
    expect(new Set(stickyPalette.map((colour) => colour.fill)).size).toBe(stickyPalette.length);
    expect(stickyPalette.every((colour) => /^#[0-9A-F]{6}$/.test(colour.fill))).toBe(true);
    expect(stickyPalette.some((colour) => colour.id === defaultStickyColourId)).toBe(true);
    expect(stickyColour(defaultStickyColourId).name).toBe('Yellow');
  });

  it('keeps the colour chosen when the note is added', () => {
    const draft = createStickyNote('  Ship the palette  ', 'teal', 'note-1');
    expect(draft).toEqual({
      note: { id: 'note-1', text: 'Ship the palette', colourId: 'teal' },
    });
  });

  it('rejects a blank note and a colour outside the palette', () => {
    expect(createStickyNote('   ', 'yellow', 'note-2')).toEqual({ error: 'empty' });
    expect(createStickyNote('Hello', 'navy', 'note-3')).toEqual({ error: 'unknown-colour' });
    expect(createStickyNote('a'.repeat(maxStickyTextLength + 1), 'blue', 'note-4')).toEqual({
      error: 'too-long',
    });
  });
});
