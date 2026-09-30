package com.atlassian.meridian

/**
 * Whiteboard sticky-note colours. Keep ids and fills aligned with the Swift
 * client and the browser companion palette.
 */
data class StickyColour(
  val id: String,
  val name: String,
  val fill: String,
)

data class StickyNote(
  val id: String,
  val text: String,
  val colourId: String,
)

enum class StickyDraftError {
  Empty,
  TooLong,
  UnknownColour,
}

sealed class StickyDraft {
  data class Created(val note: StickyNote) : StickyDraft()
  data class Rejected(val error: StickyDraftError) : StickyDraft()
}

object StickyPalette {
  const val defaultColourId = "yellow"
  const val maxTextLength = 280

  val colours: List<StickyColour> = listOf(
    StickyColour("yellow", "Yellow", "#F8E6A0"),
    StickyColour("orange", "Orange", "#F6C98A"),
    StickyColour("coral", "Coral", "#F8C8BC"),
    StickyColour("pink", "Pink", "#F6C9DC"),
    StickyColour("purple", "Purple", "#D9CEF6"),
    StickyColour("blue", "Blue", "#C9DBF8"),
    StickyColour("teal", "Teal", "#C6EDE6"),
    StickyColour("green", "Green", "#D7EEB8"),
  )

  fun colour(id: String): StickyColour = colours.firstOrNull { it.id == id } ?: colours.first()

  fun createNote(text: String, colourId: String, id: String): StickyDraft {
    val trimmed = text.trim()
    if (trimmed.isEmpty()) return StickyDraft.Rejected(StickyDraftError.Empty)
    if (trimmed.length > maxTextLength) return StickyDraft.Rejected(StickyDraftError.TooLong)
    if (colours.none { it.id == colourId }) return StickyDraft.Rejected(StickyDraftError.UnknownColour)
    return StickyDraft.Created(StickyNote(id, trimmed, colourId))
  }
}
