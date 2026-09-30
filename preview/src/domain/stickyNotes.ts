/** Whiteboard sticky-note colours. Keep ids and fills aligned with the Swift and Kotlin clients. */
export type StickyColour = {
  id: string;
  name: string;
  fill: string;
};

export type StickyNote = {
  id: string;
  text: string;
  colourId: string;
};

export type StickyDraftError = 'empty' | 'too-long' | 'unknown-colour';

export const defaultStickyColourId = 'yellow';
export const maxStickyTextLength = 280;

export const stickyPalette: readonly StickyColour[] = [
  { id: 'yellow', name: 'Yellow', fill: '#F8E6A0' },
  { id: 'orange', name: 'Orange', fill: '#F6C98A' },
  { id: 'coral', name: 'Coral', fill: '#F8C8BC' },
  { id: 'pink', name: 'Pink', fill: '#F6C9DC' },
  { id: 'purple', name: 'Purple', fill: '#D9CEF6' },
  { id: 'blue', name: 'Blue', fill: '#C9DBF8' },
  { id: 'teal', name: 'Teal', fill: '#C6EDE6' },
  { id: 'green', name: 'Green', fill: '#D7EEB8' },
];

export function stickyColour(id: string): StickyColour {
  return stickyPalette.find((colour) => colour.id === id) ?? stickyPalette[0];
}

export function createStickyNote(
  text: string,
  colourId: string,
  id: string,
): { note: StickyNote } | { error: StickyDraftError } {
  const trimmed = text.trim();
  if (!trimmed) return { error: 'empty' };
  if (trimmed.length > maxStickyTextLength) return { error: 'too-long' };
  if (!stickyPalette.some((colour) => colour.id === colourId)) return { error: 'unknown-colour' };
  return { note: { id, text: trimmed, colourId } };
}
