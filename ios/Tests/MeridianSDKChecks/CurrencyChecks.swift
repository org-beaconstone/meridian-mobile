import Foundation
@testable import MeridianSDK

func runCurrencyAndStoreChecks(passed: inout Int, failed: inout Int) {
  func check(_ name: String, _ condition: Bool) {
    if condition {
      print("  ✓ \(name)")
      passed += 1
    } else {
      print("  ✗ \(name)")
      failed += 1
    }
  }

  print("21. CurrencyCode wire values...")
  check("gbp is GBP", CurrencyCode.gbp.rawValue == "GBP")
  check("eur is EUR", CurrencyCode.eur.rawValue == "EUR")

  let encoder = JSONEncoder()
  let decoder = JSONDecoder()

  print("22. MonetaryAmount integer JSON...")
  let tenThousand = MonetaryAmount(minorUnits: 1_000_000, currency: .eur)
  let zeroGbp = MonetaryAmount(minorUnits: 0, currency: .gbp)
  let oneCent = MonetaryAmount(minorUnits: 1, currency: .eur)
  do {
    let encoded = try encoder.encode(tenThousand)
    let text = String(decoding: encoded, as: UTF8.self)
    let decoded = try decoder.decode(MonetaryAmount.self, from: encoded)
    check("10,000.00 EUR has no decimal in JSON", !text.contains("."))
    check("10,000.00 EUR minor units survive", decoded.minorUnits == 1_000_000 && decoded.currency == .eur)
    let zeroData = try encoder.encode(zeroGbp)
    let zero = try decoder.decode(MonetaryAmount.self, from: zeroData)
    check("zero GBP round trip", zero == zeroGbp)
    let centData = try encoder.encode(oneCent)
    let cent = try decoder.decode(MonetaryAmount.self, from: centData)
    check("single cent round trip", cent.minorUnits == 1 && cent.currency == .eur)
  } catch {
    check("MonetaryAmount JSON \(error)", false)
  }

  print("23. Boundary formatting...")
  check("zero GBP", formatMonetaryAmount(zeroGbp) == "£0.00")
  check("zero EUR", formatMonetaryAmount(MonetaryAmount(minorUnits: 0, currency: .eur)) == "€0.00")
  check("one pence", formatMonetaryAmount(MonetaryAmount(minorUnits: 1, currency: .gbp)) == "£0.01")
  check("one cent", formatMonetaryAmount(oneCent) == "€0.01")
  check("10,000.00 EUR", tenThousand.formatted == "€10,000.00")
  check("10,000.00 GBP", formatMonetaryAmount(MonetaryAmount(minorUnits: 1_000_000, currency: .gbp)) == "£10,000.00")

  print("24. DynamicProvider and European transaction...")
  check("baseline is Adyen and Worldpay", DynamicProvider.baseline.map(\.id) == [.adyen, .worldpay])
  check("baseline currencies are GBP", DynamicProvider.baseline.allSatisfy { $0.currencies == [.gbp] })
  do {
    let transaction = try EuropeanTransaction(
      id: "ept-10000",
      reference: "EU-10000",
      recipientId: "northline-studio",
      amount: tenThousand,
      provider: .adyenCard,
      method: .card,
      status: .pending,
      note: "Corridor rehearsal",
      idempotencyKey: "idem-eur-1"
    )
    let encoded = try encoder.encode(transaction)
    let decoded = try decoder.decode(EuropeanPaymentTransaction.self, from: encoded)
    check("EuropeanTransaction round trip", decoded == transaction)
    let text = String(decoding: encoded, as: UTF8.self)
    check("encoded currency is EUR", text.contains("\"EUR\""))
    check("idempotency key kept", decoded.idempotencyKey == "idem-eur-1")
  } catch {
    check("European transaction JSON \(error)", false)
  }
  do {
    _ = try EuropeanPaymentTransaction(
      id: "bad",
      reference: "x",
      recipientId: "northline-studio",
      amount: MonetaryAmount(minorUnits: 100, currency: .gbp),
      provider: .worldpayBank,
      method: .bank,
      status: .completed
    )
    check("GBP rejected for European transaction", false)
  } catch {
    check("GBP rejected for European transaction", true)
  }
  let unknownProvider = """
  {"id":"unlisted","name":"Unlisted","methods":["card"],"currencies":["EUR"]}
  """.data(using: .utf8)!
  do {
    _ = try decoder.decode(DynamicProvider.self, from: unknownProvider)
    check("unknown provider rejected", false)
  } catch {
    check("unknown provider rejected", true)
  }

  print("25. Isolated GBPStore and EURStore...")
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("meridian-cache-\(UUID().uuidString)", isDirectory: true)
  let legacy = """
  {
    "version": 1,
    "balance": 1248050,
    "transactions": [
      {
        "id": "txn-001",
        "reference": "REF-1",
        "recipientId": "birch-bloom",
        "name": "Birch & Bloom",
        "category": "Food & drink",
        "amount": 3500,
        "date": "2026-09-05",
        "provider": "worldpay",
        "method": "bank",
        "status": "completed",
        "note": "Breakfast"
      }
    ],
    "budgets": []
  }
  """
  do {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let legacyURL = root.appendingPathComponent("payments.json")
    let legacyData = Data(legacy.utf8)
    try legacyData.write(to: legacyURL)
    let cache = try IsolatedPaymentCache(rootDirectory: root)
    let legacyAfter = try Data(contentsOf: legacyURL)
    let gbp = try cache.gbpStore.load()
    let eur = try cache.eurStore.load()
    check("legacy file untouched", legacyAfter == legacyData)
    check("legacy defaults to GBPStore", gbp.count == 1 && gbp[0].minorUnits == 3500 && gbp[0].currency == .gbp)
    check("legacy does not fill EURStore", eur.isEmpty)
    check(
      "store paths are isolated",
      cache.gbpStore.paymentsFile.path.contains("/GBPStore/")
        && cache.eurStore.paymentsFile.path.contains("/EURStore/")
    )

    let gbpBytes = try cache.gbpStore.readBytes()
    let eurRecord = CachedPaymentRecord(
      id: "eur-1",
      minorUnits: 1,
      currency: .eur,
      reference: "cent",
      recipientId: "northline-studio",
      providerId: .adyen,
      method: .card,
      status: .pending,
      idempotencyKey: "idem-eur-1"
    )
    try cache.eurStore.save([eurRecord])
    check("EUR write leaves GBPStore bytes unchanged", (try cache.gbpStore.readBytes()) == gbpBytes)
    check("EUR row is one cent", (try cache.eurStore.load()).first?.minorUnits == 1)

    let replacement = """
    {"records":[{"id":"other","minorUnits":99,"currency":"GBP","reference":"","recipientId":"birch-bloom","providerId":"adyen","method":"card","status":"completed","note":"","idempotencyKey":""}]}
    """.data(using: .utf8)!
    try cache.importCached(replacement)
    check("existing GBPStore is not overwritten", (try cache.gbpStore.load()).first?.id == "txn-001")

    let beforeReject = try cache.gbpStore.readBytes()
    do {
      try cache.gbpStore.save([eurRecord])
      check("GBPStore rejects EUR", false)
    } catch {
      check("GBPStore rejects EUR", (try cache.gbpStore.readBytes()) == beforeReject)
    }
  } catch {
    check("store checks \(error)", false)
  }

  // The upsert above keeps a key only when one was already stored. Seed one explicitly.
  let keyRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("meridian-key-\(UUID().uuidString)", isDirectory: true)
  do {
    let cache = try IsolatedPaymentCache(rootDirectory: keyRoot)
    try cache.gbpStore.save([
      CachedPaymentRecord(
        id: "pay-1",
        minorUnits: 100,
        currency: .gbp,
        reference: "held",
        recipientId: "birch-bloom",
        providerId: .adyen,
        method: .card,
        status: .pending,
        idempotencyKey: "same-key"
      )
    ])
    try cache.gbpStore.upsert(
      CachedPaymentRecord(
        id: "pay-1",
        minorUnits: 100,
        currency: .gbp,
        reference: "held",
        recipientId: "birch-bloom",
        providerId: .adyen,
        method: .card,
        status: .pending,
        idempotencyKey: ""
      )
    )
    check("uncertain retry keeps idempotency key", (try cache.gbpStore.load()).first?.idempotencyKey == "same-key")
  } catch {
    check("idempotency \(error)", false)
  }

  let splitRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("meridian-split-\(UUID().uuidString)", isDirectory: true)
  do {
    try FileManager.default.createDirectory(at: splitRoot, withIntermediateDirectories: true)
    let payload = """
    {"GBPStore":[{"id":"moved","minorUnits":1,"currency":"EUR","reference":"","recipientId":"northline-studio","providerId":"adyen","method":"card","status":"pending","note":"","idempotencyKey":"k"}]}
    """
    try payload.data(using: .utf8)!.write(to: splitRoot.appendingPathComponent("cache.json"))
    let cache = try IsolatedPaymentCache(rootDirectory: splitRoot)
    check("EUR row inside GBPStore key is rehomed", (try cache.gbpStore.load()).isEmpty)
    check("rehomed row lands in EURStore", (try cache.eurStore.load()).first?.id == "moved")
  } catch {
    check("rehome \(error)", false)
  }

  let corruptRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("meridian-corrupt-\(UUID().uuidString)", isDirectory: true)
  do {
    let cache = try IsolatedPaymentCache(rootDirectory: corruptRoot)
    try Data("not-json".utf8).write(to: cache.gbpStore.paymentsFile)
    let before = try cache.gbpStore.readBytes()
    do {
      _ = try cache.gbpStore.load()
      check("corrupt GBPStore fails closed", false)
    } catch {
      check("corrupt GBPStore left unchanged", (try cache.gbpStore.readBytes()) == before)
    }
    let fraction = """
    [{"id":"bad","minorUnits":10.5,"currency":"GBP","providerId":"adyen","method":"card","status":"completed"}]
    """.data(using: .utf8)!
    let clean = try IsolatedPaymentCache(
      rootDirectory: FileManager.default.temporaryDirectory
        .appendingPathComponent("meridian-fraction-\(UUID().uuidString)", isDirectory: true)
    )
    do {
      try clean.importCached(fraction)
      check("fractional minor units rejected", false)
    } catch {
      check("fractional minor units rejected", (try clean.gbpStore.load()).isEmpty)
    }
  } catch {
    check("corrupt \(error)", false)
  }
}
