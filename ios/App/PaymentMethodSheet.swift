import SwiftUI
import MeridianSDK

struct PaymentMethodSheet: View {
  let model: PaymentMethodSheetModel
  let selection: PaymentMethod
  let onSelect: (PaymentMethod) -> Void
  let onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Capsule()
        .fill(Color.secondary.opacity(0.35))
        .frame(width: 36, height: 4)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityHidden(true)
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Payment method").font(.title3).fontWeight(.semibold)
          Text("GBP · United Kingdom").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button("Done", action: onClose).frame(minWidth: 48, minHeight: 48)
      }
      if model.loading {
        VStack(spacing: 8) {
          ForEach(0..<model.placeholderCount, id: \.self) { _ in
            RoundedRectangle(cornerRadius: 8)
              .fill(Color(red: 0.894, green: 0.910, blue: 0.882))
              .frame(maxWidth: .infinity)
              .frame(height: 48)
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading payment methods")
      } else if model.options.isEmpty {
        Text("No payment method is available for this corridor.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
      } else {
        VStack(spacing: 8) {
          ForEach(Array(model.options.enumerated()), id: \.element.id) { _, option in
            Button {
              if option.selectable { onSelect(option.method) }
            } label: {
              HStack(spacing: 8) {
                radio(selected: selection == option.method && option.selectable)
                VStack(alignment: .leading, spacing: 4) {
                  Text(option.title)
                    .foregroundStyle(option.selectable ? Color.primary : Color.secondary)
                  if let helper = option.helperText {
                    Text(helper)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .multilineTextAlignment(.leading)
                  }
                }
                Spacer(minLength: 0)
              }
              .frame(minHeight: 48)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!option.selectable)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(option.accessibilityLabel)
            .accessibilityHint(option.helperText ?? "")
            .accessibilityAddTraits(
              selection == option.method && option.selectable ? .isSelected : AccessibilityTraits()
            )
          }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Payment method")
      }
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 24)
    .frame(maxWidth: .infinity)
    .background(Color.white)
    .accessibilityAddTraits(.isModal)
  }

  private func radio(selected: Bool) -> some View {
    ZStack {
      Circle()
        .stroke(selected ? Color(red: 0.094, green: 0.408, blue: 0.859) : Color.secondary, lineWidth: 2)
        .frame(width: 22, height: 22)
      if selected {
        Circle()
          .fill(Color(red: 0.094, green: 0.408, blue: 0.859))
          .frame(width: 12, height: 12)
      }
    }
    .frame(width: 48, height: 48)
    .accessibilityHidden(true)
  }
}
