import SwiftUI
import MeridianSDK
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct MethodLogo: View {
  let label: String
  let name: String

  var body: some View {
    Text(label)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.white)
      .frame(width: 40, height: 40)
      .background(Color(red: 0.078, green: 0.173, blue: 0.208))
      .clipShape(Circle())
      .accessibilityLabel("Logo for \(name)")
  }
}

struct SelectorSkeleton: View {
  var label: String = "Loading payment methods"

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ForEach(0..<3, id: \.self) { _ in
        HStack(spacing: 12) {
          Circle().fill(Color.gray.opacity(0.22)).frame(width: 40, height: 40)
          VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.22)).frame(width: 168, height: 14)
            RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.22)).frame(width: 108, height: 10)
          }
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
  }
}

struct SelectorEmptyState: View {
  let message: String

  var body: some View {
    Text(message)
      .font(.body)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
      .accessibilityLabel(message)
  }
}

struct SelectorOverlay<Content: View>: View {
  let title: String
  let fullScreen: Bool
  let onDismiss: () -> Void
  @ViewBuilder var content: () -> Content

  var body: some View {
    ZStack(alignment: fullScreen ? .center : .bottom) {
      Color.black.opacity(0.42)
        .ignoresSafeArea()
        .onTapGesture(perform: onDismiss)
        .accessibilityLabel("Dismiss \(title)")
        .accessibilityAddTraits(.isButton)
      VStack(alignment: .leading, spacing: 0) {
        if !fullScreen {
          Capsule()
            .fill(Color.gray.opacity(0.45))
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .accessibilityHidden(true)
        }
        HStack {
          Text(title).font(.title3.weight(.semibold))
          Spacer()
          Button("Close", action: onDismiss)
        }
        .padding(.horizontal, 20)
        .padding(.top, fullScreen ? 20 : 14)
        .padding(.bottom, 8)
        ScrollView {
          content()
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .ignoresSafeArea(edges: fullScreen ? .all : .bottom)
      .frame(maxWidth: fullScreen ? .infinity : 560, maxHeight: fullScreen ? .infinity : 560, alignment: .top)
      .frame(maxWidth: .infinity, maxHeight: fullScreen ? .infinity : nil, alignment: fullScreen ? .center : .bottom)
      .background(selectorCanvas)
      .clipShape(RoundedRectangle(cornerRadius: fullScreen ? 0 : 22, style: .continuous))
    }
    .accessibilityAddTraits(.isModal)
  }

  private var selectorCanvas: Color {
    #if os(iOS)
    Color(uiColor: .systemBackground)
    #else
    Color(nsColor: .windowBackgroundColor)
    #endif
  }
}

struct MethodSelectorContent: View {
  let loading: Bool
  let groups: [MethodGroup]
  let selectedId: String?
  let onSelect: (MethodChoice) -> Void

  var body: some View {
    let state = methodSelectorState(loading: loading, groups: groups)
    switch state {
    case .loading:
      SelectorSkeleton()
    case .empty:
      SelectorEmptyState(message: methodSelectorEmptyMessage)
    case .ready:
      VStack(alignment: .leading, spacing: 18) {
        ForEach(groups) { group in
          VStack(alignment: .leading, spacing: 8) {
            Text(group.descriptor)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.secondary)
              .accessibilityAddTraits(.isHeader)
            ForEach(group.methods) { choice in
              Button {
                onSelect(choice)
              } label: {
                HStack(spacing: 12) {
                  MethodLogo(label: choice.logoLabel, name: choice.providerName)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(choice.providerName).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(choice.methodLabel).font(.caption).foregroundStyle(.secondary)
                    Text(eligibilityLabel(eligible: choice.eligible))
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(choice.eligible ? Color(red: 0.1, green: 0.45, blue: 0.28) : Color(red: 0.55, green: 0.28, blue: 0.05))
                  }
                  Spacer()
                  if choice.id == selectedId {
                    Image(systemName: "checkmark")
                      .foregroundStyle(Color(red: 0.078, green: 0.173, blue: 0.208))
                      .accessibilityHidden(true)
                  }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(choice.id == selectedId ? Color.gray.opacity(0.12) : Color.gray.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .opacity(choice.eligible ? 1 : 0.5)
              }
              .buttonStyle(.plain)
              .disabled(!choice.eligible)
              .accessibilityLabel("\(choice.providerName), \(choice.methodLabel), \(eligibilityLabel(eligible: choice.eligible))")
            }
          }
        }
      }
    }
  }
}

struct BankSelectorContent: View {
  let loading: Bool
  let banks: [BankChoice]
  let selectedId: String?
  let onSelect: (BankChoice) -> Void
  @State private var query = ""

  var body: some View {
    let state = bankSelectorState(loading: loading, banks: banks, query: query)
    VStack(alignment: .leading, spacing: 12) {
      TextField("Search banks", text: $query)
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel("Search banks")
      switch state {
      case .loading:
        SelectorSkeleton(label: "Loading banks")
      case .empty:
        SelectorEmptyState(message: bankEmptyMessage(banks: banks, query: query))
      case .ready:
        VStack(alignment: .leading, spacing: 8) {
          ForEach(filterBanks(banks, query: query)) { bank in
            Button {
              onSelect(bank)
            } label: {
              HStack(spacing: 12) {
                MethodLogo(label: logoLabel(for: bank.name), name: bank.name)
                Text(bank.name).foregroundStyle(.primary)
                Spacer()
                if bank.id == selectedId {
                  Image(systemName: "checkmark")
                    .accessibilityHidden(true)
                }
              }
              .padding(12)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(bank.id == selectedId ? Color.gray.opacity(0.12) : Color.gray.opacity(0.05))
              .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(bank.name)
          }
        }
      }
    }
  }
}

struct CatalogChoiceButton: View {
  let title: String
  let subtitle: String
  let logo: String
  let enabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        MethodLogo(label: logo, name: title)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
          Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Text("Change").font(.caption).foregroundStyle(.secondary)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.gray.opacity(0.08))
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .accessibilityLabel("\(title), \(subtitle)")
  }
}
