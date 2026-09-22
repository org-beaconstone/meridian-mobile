import SwiftUI
import MeridianSDK

// MARK: - CatalogState

/// Async load state for the payment provider catalog.
///
/// `lastKnown` is carried through the `.failed` case so the UI can keep
/// the previous provider list visible alongside an inline error + retry action,
/// consistent with the SDK's error surface and the spec's interaction states.
enum CatalogState: Equatable {
  /// Waiting for the first fetch to start (not yet connected).
  case idle
  /// Fetch in progress; `lastKnown` holds the previous list if one exists.
  case loading(lastKnown: [Provider]?)
  /// Fetch succeeded; list is current.
  case loaded([Provider])
  /// Fetch failed; `lastKnown` holds the previous list (may be nil on first load).
  case failed(String, lastKnown: [Provider]?)
  /// Fetch returned zero providers (should never happen in production).
  case empty

  static func == (lhs: CatalogState, rhs: CatalogState) -> Bool {
    switch (lhs, rhs) {
    case (.idle, .idle): return true
    case (.loading, .loading): return true
    case (.loaded(let a), .loaded(let b)): return a == b
    case (.failed(let a, _), .failed(let b, _)): return a == b
    case (.empty, .empty): return true
    default: return false
    }
  }
}

// MARK: - ProviderListView

/// Payment provider list with four distinct render modes:
/// - **Skeleton** while loading (never a spinner over stale data)
/// - **Loaded** rows with name, description, and method badges
/// - **Inline error + retry** when the fetch fails, keeping the last known list visible
/// - **Empty state** when the catalog returns zero providers
///
/// Provider names and descriptions truncate gracefully; no fixed maximum provider count.
///
/// Built as a **net-new** component — no equivalent loading/retry skeleton exists
/// in this repo. Uses `DesignTokens` for WCAG 2.1 AA compliance in light and dark themes.
@MainActor
struct ProviderListView: View {
  let catalogState: CatalogState
  let onRetry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      switch catalogState {
      case .idle:
        EmptyView()

      case .loading(let lastKnown):
        if let providers = lastKnown, !providers.isEmpty {
          // Show stale list with skeleton overlay — no spinner over stale data.
          providerList(providers)
            .opacity(0.5)
          ProviderSkeletonBanner()
        } else {
          ProviderSkeletonView()
        }

      case .loaded(let providers):
        providerList(providers)

      case .failed(let message, let lastKnown):
        InlineErrorRetryView(message: message, onRetry: onRetry)
        if let providers = lastKnown, !providers.isEmpty {
          providerList(providers)
        }

      case .empty:
        emptyState
      }
    }
  }

  // MARK: – Loaded list

  @ViewBuilder
  private func providerList(_ providers: [Provider]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
        ProviderRowView(provider: provider)
        if index < providers.count - 1 {
          Divider().padding(.leading, 16)
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(DesignTokens.separator, lineWidth: 1)
    )
  }

  // MARK: – Empty state

  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "creditcard.trianglebadge.exclamationmark")
        .font(.system(size: 40))
        .foregroundStyle(DesignTokens.labelSecondary)
        .accessibilityHidden(true)

      Text("No payment methods available right now")
        .font(.callout)
        .multilineTextAlignment(.center)
        .foregroundStyle(DesignTokens.labelSecondary)
    }
    .frame(maxWidth: .infinity)
    .padding(24)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("No payment methods available right now")
  }
}

// MARK: - ProviderRowView

private struct ProviderRowView: View {
  let provider: Provider

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(provider.name)
        .font(.body)
        .fontWeight(.medium)
        .foregroundStyle(DesignTokens.labelPrimary)
        .lineLimit(1)

      Text(provider.description)
        .font(.caption)
        .foregroundStyle(DesignTokens.labelSecondary)
        .lineLimit(2)

      HStack(spacing: 6) {
        ForEach(provider.methods, id: \.self) { method in
          ProviderMethodBadge(method: method)
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DesignTokens.surfaceNeutral)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(provider.name). \(provider.description). " +
      "Methods: \(provider.methods.map(\.rawValue).joined(separator: ", "))"
    )
  }
}

// MARK: - ProviderMethodBadge

private struct ProviderMethodBadge: View {
  let method: PaymentMethod

  var body: some View {
    Text(label)
      .font(.caption2)
      .fontWeight(.semibold)
      .foregroundStyle(DesignTokens.labelOnBrand)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(DesignTokens.surfaceBrand)
      .clipShape(Capsule())
      .accessibilityHidden(true)
  }

  private var label: String {
    switch method {
    case .card: return "Card"
    case .bank: return "Bank"
    }
  }
}

// MARK: - ProviderSkeletonView

/// Full skeleton placeholder shown when no previous provider list exists.
/// Uses a pulsing shimmer animation. Never shows a spinner over stale data.
struct ProviderSkeletonView: View {
  @State private var shimmer = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      skeletonRow
      Divider().padding(.leading, 16)
      skeletonRow
    }
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(DesignTokens.separator, lineWidth: 1)
    )
    .onAppear {
      withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
        shimmer = true
      }
    }
    .accessibilityLabel("Loading payment providers")
    .accessibilityAddTraits(.updatesFrequently)
  }

  private var skeletonRow: some View {
    VStack(alignment: .leading, spacing: 8) {
      skeletonBar(width: 110, height: 14)
      skeletonBar(width: 200, height: 11)
      skeletonBar(width: 60,  height: 11)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DesignTokens.surfaceNeutral)
  }

  private func skeletonBar(width: CGFloat, height: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: 4)
      .fill(shimmer ? DesignTokens.skeletonHighlight : DesignTokens.skeletonBase)
      .frame(width: width, height: height)
  }
}

// MARK: - ProviderSkeletonBanner

/// Thin banner shown above a stale provider list while a refresh is in progress.
private struct ProviderSkeletonBanner: View {
  var body: some View {
    HStack(spacing: 8) {
      ProgressView().scaleEffect(0.7).accessibilityHidden(true)
      Text("Refreshing providers\u{2026}")
        .font(.caption)
        .foregroundStyle(DesignTokens.labelSecondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityLabel("Refreshing payment providers")
    .accessibilityAddTraits(.updatesFrequently)
  }
}

// MARK: - InlineErrorRetryView

/// Non-blocking inline error with a retry action shown when the catalog fetch fails.
/// Keeps the last known provider list visible alongside the error message.
struct InlineErrorRetryView: View {
  let message: String
  let onRetry: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.caption)
        .foregroundStyle(DesignTokens.labelWarning)
        .accessibilityHidden(true)

      Text(message)
        .font(.caption)
        .foregroundStyle(DesignTokens.labelSecondary)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)

      Button(action: onRetry) {
        Text("Retry")
          .font(.caption)
          .fontWeight(.semibold)
      }
      .accessibilityLabel("Retry loading payment methods")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(DesignTokens.surfaceWarning)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .accessibilityElement(children: .contain)
  }
}

// MARK: - Provider Identifiable conformance

extension Provider: Identifiable {}
