import Foundation

// MARK: - Catalog-driven payment selection

public struct MethodChoice: Hashable, Identifiable {
  public let id: String
  public let method: String
  public let providerId: String
  public let providerName: String
  public let descriptor: String
  public let logoUrl: String?
  public let logoLabel: String
  public let methodLabel: String
  public let eligible: Bool
  public let requiresBank: Bool
  public let banks: [BankChoice]

  public init(
    id: String,
    method: String,
    providerId: String,
    providerName: String,
    descriptor: String,
    logoUrl: String?,
    logoLabel: String,
    methodLabel: String,
    eligible: Bool,
    requiresBank: Bool,
    banks: [BankChoice]
  ) {
    self.id = id
    self.method = method
    self.providerId = providerId
    self.providerName = providerName
    self.descriptor = descriptor
    self.logoUrl = logoUrl
    self.logoLabel = logoLabel
    self.methodLabel = methodLabel
    self.eligible = eligible
    self.requiresBank = requiresBank
    self.banks = banks
  }
}

public struct MethodGroup: Hashable, Identifiable {
  public let descriptor: String
  public let methods: [MethodChoice]

  public var id: String { descriptor }

  public init(descriptor: String, methods: [MethodChoice]) {
    self.descriptor = descriptor
    self.methods = methods
  }
}

public struct SelectionState: Equatable {
  public var methodId: String?
  public var bankId: String?

  public init(methodId: String? = nil, bankId: String? = nil) {
    self.methodId = methodId
    self.bankId = bankId
  }
}

public enum SelectorContentState: Equatable {
  case loading
  case empty
  case ready
}

public let methodSelectorEmptyMessage = "No payment methods are available."
public let bankSelectorEmptyMessage = "No banks are available for this method."

public func logoLabel(for name: String) -> String {
  let parts = name.split { !$0.isLetter && !$0.isNumber }
  let initials = parts.prefix(2).compactMap { $0.first }.map { String($0) }.joined()
  let label = initials.uppercased()
  if !label.isEmpty {
    return String(label.prefix(2))
  }
  return "?"
}

public func methodLabel(for method: String) -> String {
  switch method.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
  case "card":
    return "Debit card"
  case "bank":
    return "Bank payment"
  case "":
    return "Payment method"
  default:
    let trimmed = method.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
  }
}

public func eligibilityLabel(eligible: Bool) -> String {
  eligible ? "Eligible" : "Unavailable"
}

public func payableMethod(_ raw: String) -> PaymentMethod? {
  PaymentMethod(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
}

public func descriptor(for provider: Provider) -> String {
  let description = provider.description.trimmingCharacters(in: .whitespacesAndNewlines)
  if !description.isEmpty { return description }
  let name = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
  if !name.isEmpty { return name }
  return "Payment methods"
}

public func methodRequiresBank(_ method: String, provider: Provider) -> Bool {
  if let requiresBank = provider.requiresBank {
    return requiresBank
  }
  return method.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "bank"
}

public func methodGroups(from providers: [Provider]) -> [MethodGroup] {
  var order: [String] = []
  var buckets: [String: [MethodChoice]] = [:]
  for provider in providers {
    let group = descriptor(for: provider)
    if buckets[group] == nil {
      order.append(group)
      buckets[group] = []
    }
    for (index, method) in provider.methods.enumerated() {
      let name = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
      let choice = MethodChoice(
        id: "\(provider.id)|\(method)|\(index)",
        method: method,
        providerId: provider.id,
        providerName: name.isEmpty ? methodLabel(for: method) : name,
        descriptor: group,
        logoUrl: provider.logoUrl,
        logoLabel: logoLabel(for: name.isEmpty ? method : name),
        methodLabel: methodLabel(for: method),
        eligible: provider.eligible,
        requiresBank: methodRequiresBank(method, provider: provider),
        banks: provider.banks
      )
      buckets[group, default: []].append(choice)
    }
  }
  return order.compactMap { key in
    guard let methods = buckets[key], !methods.isEmpty else { return nil }
    return MethodGroup(descriptor: key, methods: methods)
  }
}

public func allMethodChoices(from providers: [Provider]) -> [MethodChoice] {
  methodGroups(from: providers).flatMap(\.methods)
}

public func methodChoice(id: String?, in providers: [Provider]) -> MethodChoice? {
  guard let id else { return nil }
  return allMethodChoices(from: providers).first { $0.id == id }
}

public func reconciledSelection(_ current: SelectionState, providers: [Provider]) -> SelectionState {
  let choices = allMethodChoices(from: providers)
  let method = choices.first { $0.id == current.methodId && $0.eligible }
    ?? choices.first { $0.eligible }
  let bankId: String? = {
    guard let method, method.requiresBank else { return nil }
    guard let currentId = current.bankId else { return nil }
    return method.banks.contains { $0.id == currentId } ? currentId : nil
  }()
  return SelectionState(methodId: method?.id, bankId: bankId)
}

public func filterBanks(_ banks: [BankChoice], query: String) -> [BankChoice] {
  let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.isEmpty { return banks }
  return banks.filter {
    $0.name.localizedCaseInsensitiveContains(trimmed) || $0.id.localizedCaseInsensitiveContains(trimmed)
  }
}

public func bankEmptyMessage(banks: [BankChoice], query: String) -> String {
  if banks.isEmpty { return bankSelectorEmptyMessage }
  let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
  return "No banks match \"\(trimmed)\"."
}

public func methodSelectorState(loading: Bool, groups: [MethodGroup]) -> SelectorContentState {
  if loading { return .loading }
  if groups.isEmpty || groups.allSatisfy({ $0.methods.isEmpty }) { return .empty }
  return .ready
}

public func bankSelectorState(loading: Bool, banks: [BankChoice], query: String) -> SelectorContentState {
  if loading { return .loading }
  if filterBanks(banks, query: query).isEmpty { return .empty }
  return .ready
}

public func isRegularSelectorWidth(sizeClassRegular: Bool, widthPoints: Double) -> Bool {
  sizeClassRegular || widthPoints >= 768
}

public func selectorUsesFullScreen(isRegularWidth: Bool, isAccessibilityText: Bool) -> Bool {
  isRegularWidth || isAccessibilityText
}
