import Foundation

/// Decodes either the legacy two-provider catalog or the dynamic methods catalog.
/// Unknown provider ids are dropped so a newer document cannot crash the client
/// or introduce a provider outside the Adyen card / Worldpay bank baseline.
public enum PaymentCatalogDecoder {
  public static func decode(_ data: Data) -> CatalogResponse? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    return decodeObject(root)
  }

  static func decodeObject(_ root: [String: Any]) -> CatalogResponse {
    let dynamic = isDynamic(root)
    let rows: [[String: Any]]
    if dynamic, let methods = root["methods"] as? [[String: Any]] {
      rows = methods
    } else if let providers = root["providers"] as? [[String: Any]] {
      rows = providers
    } else {
      rows = []
    }
    return CatalogResponse(
      demoDate: root["demoDate"] as? String ?? "",
      recipients: decodeRecipients(root["recipients"]),
      providers: rows.compactMap(decodeProvider),
      schema: dynamic ? "dynamic" : "legacy",
      currencies: decodeCurrencies(root["currencies"], dynamic: dynamic)
    )
  }

  private static func isDynamic(_ root: [String: Any]) -> Bool {
    let marker = ((root["schema"] as? String) ?? (root["model"] as? String) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if marker == "dynamic" { return true }
    if marker == "legacy" { return false }
    return root["methods"] is [Any] && root["providers"] == nil
  }

  private static func decodeRecipients(_ value: Any?) -> [Recipient] {
    guard let rows = value as? [[String: Any]] else { return [] }
    return rows.compactMap { row in
      guard
        let id = row["id"] as? String,
        let name = row["name"] as? String,
        let initials = row["initials"] as? String,
        let detail = row["detail"] as? String,
        let categoryRaw = row["category"] as? String,
        let category = Category(rawValue: categoryRaw),
        let color = row["color"] as? String
      else { return nil }
      return Recipient(
        id: id,
        name: name,
        initials: initials,
        detail: detail,
        category: category,
        color: color
      )
    }
  }

  private static func decodeProvider(_ row: [String: Any]) -> Provider? {
    let idRaw = (row["providerId"] as? String) ?? (row["provider"] as? String) ?? (row["id"] as? String) ?? ""
    guard let id = ProviderId(rawValue: idRaw) else { return nil }
    let fallbackName = id == .adyen ? "Adyen" : "Worldpay"
    let name = (row["name"] as? String) ?? (row["label"] as? String) ?? fallbackName
    let description = (row["description"] as? String) ?? ""
    var methods = (row["methods"] as? [String])?.compactMap(PaymentMethod.init(rawValue:)) ?? []
    if let single = (row["method"] as? String) ?? (row["rail"] as? String),
      let method = PaymentMethod(rawValue: single) {
      methods = [method]
    }
    guard let method = methods.first else { return nil }
    return Provider(id: id, name: name, description: description, methods: [method])
  }

  private static func decodeCurrencies(_ value: Any?, dynamic: Bool) -> [String] {
    guard dynamic else { return ["GBP"] }
    let codes: [String]
    if let list = value as? [Any] {
      codes = list.compactMap { item in
        if let code = item as? String { return code }
        if let object = item as? [String: Any] { return object["code"] as? String }
        return nil
      }
    } else {
      codes = []
    }
    var recognized: [String] = []
    for code in codes {
      let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
      if (normalized == "GBP" || normalized == "EUR"), !recognized.contains(normalized) {
        recognized.append(normalized)
      }
    }
    if !recognized.contains("GBP") {
      recognized.insert("GBP", at: 0)
    }
    return recognized
  }
}
