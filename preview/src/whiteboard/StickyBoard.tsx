import { useState } from 'react';
import {
  createStickyNote,
  defaultStickyColourId,
  maxStickyTextLength,
  stickyColour,
  stickyPalette,
  type StickyNote,
} from '../domain/stickyNotes';

const draftMessage: Record<string, string> = {
  empty: 'Write a sticky note before adding it.',
  'too-long': `Sticky notes can be up to ${maxStickyTextLength} characters.`,
  'unknown-colour': 'Choose a colour from the palette.',
};

export function StickyBoard() {
  const [colourId, setColourId] = useState(defaultStickyColourId);
  const [text, setText] = useState('');
  const [notes, setNotes] = useState<StickyNote[]>([]);
  const [draftError, setDraftError] = useState('');

  function addNote() {
    const draft = createStickyNote(text, colourId, crypto.randomUUID());
    if ('error' in draft) {
      setDraftError(draftMessage[draft.error]);
      return;
    }
    setNotes((current) => [draft.note, ...current]);
    setText('');
    setDraftError('');
  }

  return (
    <section className="mobile-card" aria-label="Whiteboard">
      <h1>Whiteboard</h1>
      <p>
        Browser companion rehearsal. This is not the native app. Add a sticky note and choose its
        colour. Notes stay in this browser.
      </p>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          addNote();
        }}
      >
        <fieldset>
          <legend>Sticky note colour</legend>
          <div className="colour-palette" data-testid="sticky-palette">
            {stickyPalette.map((colour) => {
              const selected = colourId === colour.id;
              return (
                <label key={colour.id} className={selected ? 'selected' : undefined}>
                  <input
                    type="radio"
                    name="sticky-colour"
                    value={colour.id}
                    checked={selected}
                    onChange={() => setColourId(colour.id)}
                  />
                  <span className="swatch" style={{ backgroundColor: colour.fill }} aria-hidden="true" />
                  <span>{colour.name}</span>
                </label>
              );
            })}
          </div>
        </fieldset>
        <label htmlFor="sticky-text">Sticky note</label>
        <textarea
          id="sticky-text"
          value={text}
          maxLength={maxStickyTextLength}
          rows={3}
          onChange={(event) => setText(event.target.value)}
          placeholder="Write a note"
        />
        {draftError && (
          <p role="alert" className="error-message">
            {draftError}
          </p>
        )}
        <button className="primary" type="submit">
          Add sticky note
        </button>
      </form>
      <div className="sticky-board" data-testid="sticky-board">
        {notes.length === 0 ? (
          <p>No sticky notes on the whiteboard yet.</p>
        ) : (
          notes.map((note) => {
            const colour = stickyColour(note.colourId);
            return (
              <article
                key={note.id}
                className="sticky-note"
                style={{ backgroundColor: colour.fill }}
                data-testid="sticky-note"
                data-colour={colour.id}
              >
                <p>{note.text}</p>
                <span>{colour.name}</span>
              </article>
            );
          })
        )}
      </div>
    </section>
  );
}
