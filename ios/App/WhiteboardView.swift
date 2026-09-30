import SwiftUI
import MeridianSDK

struct WhiteboardView: View {
  @State private var colourId = StickyPalette.defaultColourId
  @State private var text = ""
  @State private var notes: [StickyNote] = []
  @State private var message = "Choose a colour, then add a sticky note."
  @State private var messageIsError = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Whiteboard").font(.title2)
      Text("Native SwiftUI. Sticky notes stay on this device.").font(.caption).foregroundStyle(.secondary)
      Text("Sticky note colour").font(.headline)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
        ForEach(StickyPalette.colours) { colour in
          let selected = colourId == colour.id
          Button {
            colourId = colour.id
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              RoundedRectangle(cornerRadius: 4)
                .fill(Color(stickyHex: colour.fill))
                .frame(height: 22)
                .overlay(
                  RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
              Text(colour.name).font(.caption)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color(red: 0.93, green: 0.96, blue: 1) : Color.clear)
            .overlay(
              RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color(red: 0.09, green: 0.41, blue: 0.86) : Color(red: 0.84, green: 0.87, blue: 0.82), lineWidth: selected ? 2 : 1)
            )
          }
          .buttonStyle(.plain)
          .accessibilityLabel(colour.name)
          .accessibilityAddTraits(selected ? .isSelected : [])
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Sticky note colour")
      TextField("Sticky note", text: $text)
        .textFieldStyle(.roundedBorder)
      Button("Add sticky note") { addNote() }
        .buttonStyle(.borderedProminent)
      Text(message)
        .font(.callout)
        .foregroundStyle(messageIsError ? Color(red: 0.55, green: 0.15, blue: 0.09) : .secondary)
      ForEach(notes) { note in
        let colour = StickyPalette.colour(id: note.colourId)
        VStack(alignment: .leading, spacing: 8) {
          Text(note.text)
          Text(colour.name).font(.caption2).fontWeight(.semibold)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(stickyHex: colour.fill))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(colour.name) sticky note. \(note.text)")
      }
    }
  }

  private func addNote() {
    switch StickyPalette.createNote(text: text, colourId: colourId, id: UUID().uuidString) {
    case .success(let note):
      notes.insert(note, at: 0)
      text = ""
      messageIsError = false
      message = "Added a \(StickyPalette.colour(id: note.colourId).name.lowercased()) sticky note."
    case .failure(.empty):
      messageIsError = true
      message = "Write a sticky note before adding it."
    case .failure(.tooLong):
      messageIsError = true
      message = "Sticky notes can be up to \(StickyPalette.maxTextLength) characters."
    case .failure(.unknownColour):
      messageIsError = true
      message = "Choose a colour from the palette."
    }
  }
}

private extension Color {
  init(stickyHex: String) {
    let hex = stickyHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var value: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&value)
    let red = Double((value >> 16) & 0xFF) / 255
    let green = Double((value >> 8) & 0xFF) / 255
    let blue = Double(value & 0xFF) / 255
    self.init(red: red, green: green, blue: blue)
  }
}
