import SwiftUI
import MeridianSDK

/// Amount field with an en_GB £ prefix. The accessibility value is the spoken
/// pounds-and-pence phrase. The stack grows with Dynamic Type and scrolls with the form,
/// so 200% text wraps instead of clipping.
struct AmountInputField: View {
  @Binding var text: String
  var enabled: Bool

  private var evaluation: AmountEvaluation { evaluateAmount(text) }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Amount (GBP)")
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(evaluation.prefix)
          .font(.title3)
          .fixedSize()
          .accessibilityHidden(true)
        TextField("0.00", text: $text)
          .font(.title3)
          .textFieldStyle(.roundedBorder)
          .disabled(!enabled)
          .accessibilityLabel("Amount")
          .accessibilityValue(evaluation.spoken)
          .accessibilityHint("Enter pounds and pence from £0.01 to £10,000.00")
      }
      Text(evaluation.helper)
        .font(.footnote)
        .foregroundStyle(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || evaluation.isValid ? Color.secondary : Color.red)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// European IBAN field. Validation runs on each change and the helper text describes
/// length, country, and MOD-97 checksum errors.
struct IbanInputField: View {
  @Binding var text: String
  var enabled: Bool

  private var check: IbanCheck { validateIban(text) }
  private var trimmedEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Recipient IBAN")
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
      ibanField
      Text(check.helper)
        .font(.footnote)
        .foregroundStyle(trimmedEmpty || check.isValid ? Color.secondary : Color.red)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var ibanField: some View {
    let field = TextField("DE89 3704 0044 0532 0130 00", text: $text)
      .textFieldStyle(.roundedBorder)
      .autocorrectionDisabled()
      .disabled(!enabled)
      .accessibilityLabel("Recipient IBAN")
      .accessibilityValue(check.normalized.isEmpty ? "Empty" : check.normalized)
      .accessibilityHint(check.helper)
    #if os(iOS)
    return field.textInputAutocapitalization(.characters)
    #else
    return field
    #endif
  }
}

struct ChoiceRow: View {
  let title: String
  let selected: Bool
  var enabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
          .font(.body)
          .accessibilityHidden(true)
        Text(title)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
  }
}

struct GrowingButton: View {
  let title: String
  var prominent: Bool = true
  var enabled: Bool = true
  let action: () -> Void

  var body: some View {
    let label = Text(title)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 4)
    if prominent {
      Button(action: action) { label }
        .buttonStyle(.borderedProminent)
        .disabled(!enabled)
    } else {
      Button(action: action) { label }
        .buttonStyle(.bordered)
        .disabled(!enabled)
    }
  }
}
