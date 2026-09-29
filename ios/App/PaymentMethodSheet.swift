import SwiftUI
import MeridianSDK

// MARK: - Payment Method Bottom Sheet
// Shows dynamic payment methods sourced from the server catalog.
// Promotes to full-screen on iPad (regular horizontal size class) or
// when the user has enabled a large accessibility Dynamic Type size.

struct PaymentMethodSheet: View {
  let catalog: CatalogResponse?
  let onSelect: (Provider, PaymentMethod) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.horizontalSizeClass) private var sizeClass

  private var useFullScreen: Bool {
    sizeClass == .regular || typeSize >= .accessibility1
  }

  var body: some View {
    NavigationStack {
      Group {
        if let catalog {
          if catalog.providers.isEmpty {
            emptyStateView
          } else {
            methodListView(providers: catalog.providers)
          }
        } else {
          skeletonView
        }
      }
      .navigationTitle("Payment method")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    // Present as medium sheet by default; promote to large on iPad / large text.
    .presentationDetents(useFullScreen ? [.large] : [.medium, .large])
    .presentationDragIndicator(.visible)
  }

  // MARK: - Method List

  private func methodListView(providers: [Provider]) -> some View {
    let cardProviders = providers.filter { $0.methods.contains(.card) }
    let bankProviders = providers.filter { $0.methods.contains(.bank) }
    return List {
      if !cardProviders.isEmpty {
        Section("Card payments") {
          ForEach(cardProviders, id: \.id) { provider in
            ProviderRow(provider: provider, method: .card) {
              onSelect(provider, .card)
              dismiss()
            }
          }
        }
      }
      if !bankProviders.isEmpty {
        Section("Bank payments") {
          ForEach(bankProviders, id: \.id) { provider in
            ProviderRow(provider: provider, method: .bank) {
              onSelect(provider, .bank)
              dismiss()
            }
          }
        }
      }
    }
  }

  // MARK: - Empty State

  private var emptyStateView: some View {
    VStack(spacing: 16) {
      Image(systemName: "creditcard.slash")
        .font(.system(size: 48))
        .foregroundStyle(.secondary)
      Text("No payment methods available")
        .font(.headline)
      Text("Check back later or contact support.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Loading Skeleton

  private var skeletonView: some View {
    List {
      ForEach(0..<4, id: \.self) { _ in
        HStack(spacing: 12) {
          RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemFill))
            .frame(width: 40, height: 40)
          VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
              .fill(Color(.systemFill))
              .frame(width: 120, height: 14)
            RoundedRectangle(cornerRadius: 4)
              .fill(Color(.systemFill))
              .frame(width: 180, height: 12)
          }
        }
        .padding(.vertical, 4)
      }
    }
    .allowsHitTesting(false)
  }
}

// MARK: - Provider Row

private struct ProviderRow: View {
  let provider: Provider
  let method: PaymentMethod
  let onTap: () -> Void

  /// A provider is eligible when it advertises at least one method.
  private var isEligible: Bool { !provider.methods.isEmpty }

  private var accentColor: Color {
    switch provider.id.lowercased() {
    case "adyen":    return Color(red: 0.0,  green: 0.45, blue: 0.90)
    case "worldpay": return Color(red: 0.07, green: 0.53, blue: 0.45)
    default:         return .accentColor
    }
  }

  private var methodIcon: String {
    method == .card ? "creditcard.fill" : "building.columns.fill"
  }

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 8)
            .fill(accentColor.opacity(isEligible ? 1.0 : 0.3))
            .frame(width: 40, height: 40)
          Image(systemName: methodIcon)
            .foregroundStyle(.white)
            .font(.system(size: 18))
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(provider.name)
            .font(.body)
            .foregroundStyle(isEligible ? .primary : .secondary)
          Text(provider.description)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        Spacer()
        if !isEligible {
          Text("Unavailable")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(.systemFill))
            .clipShape(Capsule())
            .foregroundStyle(.secondary)
        }
      }
    }
    .disabled(!isEligible)
  }
}
