import SwiftUI

// MARK: - GroupedCardFields

/// Two-up inline row layout for expiry date (MM / YY) and CVV fields.
///
/// Built as a **net-new** grouped-field pattern — no equivalent layout component
/// exists in this repo. Each field group has a floating label above a rounded
/// bordered input, consistent with the approved Figma concept for the add-card screen.
///
/// Uses `DesignTokens` so light and dark themes both meet WCAG 2.1 AA contrast.
@MainActor
struct GroupedCardFields: View {
  @Binding var expiryMonth: String
  @Binding var expiryYear: String
  @Binding var cvv: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      expiryGroup
      cvvGroup
    }
  }

  // MARK: – Expiry date group

  private var expiryGroup: some View {
    LabeledFieldGroup(label: "Expiry date") {
      HStack(spacing: 6) {
        ConstrainedTextField(
          placeholder: "MM",
          text: $expiryMonth,
          maxLength: 2,
          accessibilityLabel: "Expiry month"
        )

        Text("/")
          .foregroundStyle(DesignTokens.labelSecondary)
          .accessibilityHidden(true)

        ConstrainedTextField(
          placeholder: "YY",
          text: $expiryYear,
          maxLength: 2,
          accessibilityLabel: "Expiry year, two digits"
        )
      }
    }
  }

  // MARK: – CVV group

  private var cvvGroup: some View {
    LabeledFieldGroup(label: "CVV") {
      ConstrainedTextField(
        placeholder: "\u{2022}\u{2022}\u{2022}",
        text: $cvv,
        maxLength: 4,
        isSecure: true,
        accessibilityLabel: "Card security code, C V V"
      )
    }
  }
}

// MARK: - LabeledFieldGroup

/// Generic container that renders a caption label above arbitrary field content,
/// with a neutral rounded-border background consistent with the existing form style.
private struct LabeledFieldGroup<Content: View>: View {
  let label: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(DesignTokens.labelSecondary)

      content()
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surfaceNeutral)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .strokeBorder(DesignTokens.separator, lineWidth: 1)
        )
    }
    .frame(maxWidth: .infinity)
  }
}

// MARK: - ConstrainedTextField

/// Text field that enforces a maximum character count and, on iOS, requests a number
/// keyboard. Secure variant uses `SecureField` for CVV entry.
private struct ConstrainedTextField: View {
  let placeholder: String
  @Binding var text: String
  let maxLength: Int
  var isSecure: Bool = false
  let accessibilityLabel: String

  var body: some View {
    inputField
      .font(.body)
      .foregroundStyle(DesignTokens.labelPrimary)
      .onChange(of: text) { _, newValue in
        if newValue.count > maxLength {
          text = String(newValue.prefix(maxLength))
        }
      }
      .accessibilityLabel(accessibilityLabel)
  }

  @ViewBuilder
  private var inputField: some View {
    if isSecure {
      SecureField(placeholder, text: $text)
    } else {
#if os(iOS)
      TextField(placeholder, text: $text)
        .keyboardType(.numberPad)
#else
      TextField(placeholder, text: $text)
#endif
    }
  }
}
