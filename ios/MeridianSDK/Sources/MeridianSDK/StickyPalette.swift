import Foundation

/// Whiteboard sticky-note colours. Keep ids and fills aligned with the Kotlin
/// client and the browser companion palette.
public struct StickyColour: Hashable, Identifiable {
  public let id: String
  public let name: String
  public let fill: String

  public init(id: String, name: String, fill: String) {
    self.id = id
    self.name = name
    self.fill = fill
  }
}

public struct StickyNote: Hashable, Identifiable {
  public let id: String
  public let text: String
  public let colourId: String

  public init(id: String, text: String, colourId: String) {
    self.id = id
    self.text = text
    self.colourId = colourId
  }
}

public enum StickyDraftError: Equatable {
  case empty
  case tooLong
  case unknownColour
}

public enum StickyPalette {
  public static let defaultColourId = "yellow"
  public static let maxTextLength = 280
  public static let colours: [StickyColour] = [
    StickyColour(id: "yellow", name: "Yellow", fill: "#F8E6A0"),
    StickyColour(id: "orange", name: "Orange", fill: "#F6C98A"),
    StickyColour(id: "coral", name: "Coral", fill: "#F8C8BC"),
    StickyColour(id: "pink", name: "Pink", fill: "#F6C9DC"),
    StickyColour(id: "purple", name: "Purple", fill: "#D9CEF6"),
    StickyColour(id: "blue", name: "Blue", fill: "#C9DBF8"),
    StickyColour(id: "teal", name: "Teal", fill: "#C6EDE6"),
    StickyColour(id: "green", name: "Green", fill: "#D7EEB8"),
  ]

  public static func colour(id: String) -> StickyColour {
    colours.first { $0.id == id } ?? colours[0]
  }

  public static func createNote(text: String, colourId: String, id: String) -> Result<StickyNote, StickyDraftError> {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return .failure(.empty) }
    if trimmed.utf16.count > maxTextLength { return .failure(.tooLong) }
    guard colours.contains(where: { $0.id == colourId }) else { return .failure(.unknownColour) }
    return .success(StickyNote(id: id, text: trimmed, colourId: colourId))
  }
}
