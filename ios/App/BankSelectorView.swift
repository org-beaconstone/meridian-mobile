import SwiftUI
import MeridianSDK

// MARK: - Searchable Bank Selector
// Displayed when the chosen payment method requires a bank choice.
// Filters the server catalog to providers that support bank transfers,
// and lets the user search by name or description.
// Promotes to full-screen on iPad or large accessibility Dynamic Type.

struct BankSelectorView: View {
  let providers: [Provider]
  let onSelect: (Provider) -> Void

  @State private var query = ""
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.horizontalSizeClass) private var sizeClass

  private var useFullScreen: Bool {
    sizeClass == .regular || typeSize >= .accessibility1
  }

  private var bankProviders: [Provider] {
    providers.filter { $0.methods.contains(.bank) }
  }

  private var filtered: [Provider] {
    guard !query.isEmpty else { return bankProviders }
    return bankProviders.filter {
      $0.name.localizedCaseInsensitiveContains(query)
        || $0.description.localizedCaseInsensitiveContains(query)
    }
  }

  var body: some View {
    NavigationStack {
      Group {
        if bankProviders.isEmpty {
          emptyStateView
        } else {
          resultsView
        }
      }
      .searchable(text: $query, prompt: "Search banks")
      .navigationTitle("Select bank")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .presentationDetents(useFullScreen ? [.large] : [.medium, .large])
    .presentationDragIndicator(.visible)
  }

  // MARK: - Results

  @ViewBuilder
  private var resultsView: some View {
    if filtered.isEmpty {
      VStack(spacing: 12) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 40))
          .foregroundStyle(.secondary)
        Text("No banks matching "\(query)"")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      List(filtered, id: \.id) { provider in
        Button {
          onSelect(provider)
          dismiss()
        } label: {
          HStack(spacing: 12) {
            Circle()
              .fill(Color(red: 0.07, green: 0.53, blue: 0.45))
              .frame(width: 40, height: 40)
              .overlay(
                Text(String(provider.name.prefix(2)).uppercased())
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.white)
              )
            VStack(alignment: .leading, spacing: 2) {
              Text(provider.name).font(.body)
              Text(provider.description).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
    }
  }

  // MARK: - Empty State

  private var emptyStateView: some View {
    VStack(spacing: 16) {
      Image(systemName: "building.columns.slash")
        .font(.system(size: 48))
        .foregroundStyle(.secondary)
      Text("No bank payment methods available")
        .font(.headline)
      Text("No providers currently support bank payments.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
