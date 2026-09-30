package com.atlassian.meridian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class StickyPaletteTest {
  @Test
  fun paletteHasNamedColoursAndDefaultsToYellow() {
    val ids = StickyPalette.colours.map { it.id }
    assertEquals(listOf("yellow", "orange", "coral", "pink", "purple", "blue", "teal", "green"), ids)
    assertEquals(ids.size, ids.toSet().size)
    assertEquals(ids.size, StickyPalette.colours.map { it.fill }.toSet().size)
    assertTrue(StickyPalette.colours.all { it.fill.matches(Regex("#[0-9A-F]{6}")) })
    assertEquals("Yellow", StickyPalette.colour(StickyPalette.defaultColourId).name)
  }

  @Test
  fun createNoteKeepsTheSelectedColour() {
    val draft = StickyPalette.createNote("  Ship the palette  ", "teal", "note-1")
    val created = draft as StickyDraft.Created
    assertEquals("note-1", created.note.id)
    assertEquals("Ship the palette", created.note.text)
    assertEquals("teal", created.note.colourId)
  }

  @Test
  fun createNoteRejectsBlankTextAndUnknownColour() {
    assertEquals(StickyDraftError.Empty, (StickyPalette.createNote("   ", "yellow", "note-2") as StickyDraft.Rejected).error)
    assertEquals(StickyDraftError.UnknownColour, (StickyPalette.createNote("Hello", "navy", "note-3") as StickyDraft.Rejected).error)
    assertEquals(
      StickyDraftError.TooLong,
      (StickyPalette.createNote("a".repeat(StickyPalette.maxTextLength + 1), "blue", "note-4") as StickyDraft.Rejected).error,
    )
  }
}
