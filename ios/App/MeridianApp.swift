import SwiftUI
import MeridianSDK
import MeridianUI
#if os(iOS)
import UIKit
#endif

@main struct MeridianApp: App {
  var body: some Scene {
    WindowGroup {
      #if os(macOS)
      MeridianView().frame(minWidth: 320, minHeight: 650)
      #else
      MeridianView()
      #endif
    }
  }
}

@MainActor struct MeridianView: View {
  @State private var endpoint = "http://127.0.0.1:8080/api/v1"
  @State private var room = "meridian-rehearsal"
  @State private var client: MeridianClient?
  @State private var state: BankState?
  @State private var catalog: CatalogResponse?
  @State private var recipient = "northline-studio"
  @State private var amount = ""
  @State private var reference = ""
  @State private var method: PaymentMethod = .card
  @State private var key = UUID().uuidString
  @State private var review = false
  @State private var busy = false
  @State private var message = "Connect to the Spring Boot API to start."
  @State private var generation = 0
  @State private var banner = SessionBannerModel.loading
  @State private var sessionFacts: SessionFacts?
  private let sessionStore = UserDefaultsSessionStore()

  var body: some View {
    ScrollView {
      AuthScreen(
        endpoint: $endpoint,
        room: $room,
        banner: banner,
        busy: busy,
        message: message,
        onSignIn: { Task { await signIn() } }
      ) {
        paymentContent
      }
      .padding(24)
      .frame(maxWidth: 550)
      .frame(maxWidth: .infinity)
    }
    .task {
      await resolveSessionOnOpen()
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        if !busy { await refresh() }
      }
    }
  }

  @ViewBuilder private var paymentContent: some View {
    if let state {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Everyday account · GBP").font(.caption)
          Text(money(state.balance)).font(.system(size: 38, weight: .medium))
          Text("Shared room: \(room)").font(.caption)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.078, green: 0.173, blue: 0.208))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        Text("Make a payment").font(.title2)
        if let catalog {
          Picker("Recipient", selection: $recipient) {
            ForEach(catalog.recipients, id: \.id) { Text($0.name).tag($0.id) }
          }
          .disabled(review || busy)
        }
        TextField("Amount (GBP)", text: $amount)
          .textFieldStyle(.roundedBorder)
          .disabled(review || busy)
        TextField("Reference", text: $reference)
          .textFieldStyle(.roundedBorder)
          .disabled(review || busy)
        // Intentionally hardcoded baseline: new providers still require a native release.
        Picker("Method", selection: $method) {
          Text("Debit card · Adyen").tag(PaymentMethod.card)
          Text("Bank payment · Worldpay").tag(PaymentMethod.bank)
        }
        .disabled(review || busy)
        if review {
          Text("Confirm \(amount) GBP to \(recipient)").font(.headline)
          Button("Confirm payment") { Task { await pay() } }
            .buttonStyle(.borderedProminent)
            .disabled(busy)
          Button("Edit details") { review = false; key = UUID().uuidString }
            .disabled(busy)
        } else {
          Button("Review payment") { beginReview() }
            .disabled(busy)
        }
        Text("Recent activity").font(.title2)
        ForEach(Array(state.transactions.reversed().prefix(8)), id: \.id) { transaction in
          HStack {
            VStack(alignment: .leading) {
              Text(transaction.name)
              Text(transaction.provider.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(money(transaction.amount))
          }
        }
        Text("September budgets").font(.title2)
        ForEach(state.budgets, id: \.category) { budget in
          HStack {
            Text(budget.category.rawValue)
            Spacer()
            Text(money(budget.limit))
          }
        }
      }
    }
  }

  private func beginReview() {
    let (value, error) = parseAmount(amount)
    guard value != nil else {
      message = error ?? "Invalid amount"
      return
    }
    guard reference.count <= 200 else {
      message = "Reference is too long"
      return
    }
    key = UUID().uuidString
    review = true
    message = "Review before confirming. No real money moves."
  }

  private func resolveSessionOnOpen() async {
    banner = .loading
    if let fields = sessionStore.loadFields() {
      endpoint = fields.endpoint
      room = fields.sessionId
    }
    guard let stored = sessionStore.load() else {
      banner = SessionBannerModel.resolve(.absent)
      message = banner.message
      return
    }
    endpoint = stored.endpoint
    room = stored.sessionId
    sessionFacts = SessionFacts(stored: stored, currentDevice: currentDeviceLabel(), now: Date())
    do {
      client = try MeridianClient(baseURL: stored.endpoint, sessionId: stored.sessionId)
    } catch {
      banner = SessionBannerModel.resolve(.failed)
      message = banner.message
      return
    }
    await refresh()
  }

  private func signIn() async {
    guard !busy else { return }
    guard room.range(of: "^[A-Za-z0-9_-]{3,64}$", options: .regularExpression) != nil else {
      message = "Invalid room"
      return
    }
    let previousClient = client
    let previousFacts = sessionFacts
    let previousRoom = previousFacts?.sessionId
    generation += 1
    let started = generation
    banner = .loading
    sessionStore.saveFields(SessionFieldMemory(endpoint: endpoint, sessionId: room))
    let now = Date()
    let device = currentDeviceLabel()
    let stored = StoredSession(
      endpoint: endpoint,
      sessionId: room,
      accountName: room,
      deviceName: device,
      authenticatedAt: now,
      expiresAt: now.addingTimeInterval(SessionTiming.lifetime)
    )
    do {
      let api = try MeridianClient(baseURL: endpoint, sessionId: room)
      try await withSessionTimeout(SessionTiming.probeTimeout) {
        _ = try await api.getHealth()
        return true
      }
      guard started == generation else { return }
      sessionStore.save(stored)
      client = api
      let facts = SessionFacts(stored: stored, currentDevice: device, now: now)
      sessionFacts = facts
      if previousRoom != room {
        state = nil
        catalog = nil
        review = false
        key = UUID().uuidString
      }
      banner = SessionBannerModel.resolve(.succeeded(facts))
      await refresh()
    } catch is CancellationError {
      return
    } catch SessionProbeError.timedOut {
      guard started == generation else { return }
      client = previousClient
      sessionFacts = previousFacts
      banner = SessionBannerModel.resolve(.timedOut)
      message = banner.message
    } catch {
      guard started == generation else { return }
      client = previousClient
      sessionFacts = previousFacts
      banner = SessionBannerModel.resolve(.failed)
      message = "API unavailable: \(error)"
    }
  }

  private func refresh() async {
    guard let client else { return }
    let started = generation
    do {
      try await withSessionTimeout(SessionTiming.probeTimeout) {
        _ = try await client.getHealth()
        return true
      }
    } catch is CancellationError {
      return
    } catch SessionProbeError.timedOut {
      guard started == generation else { return }
      banner = SessionBannerModel.resolve(.timedOut)
      message = banner.message
      return
    } catch {
      guard started == generation else { return }
      banner = SessionBannerModel.resolve(.failed)
      message = "API unavailable: \(error)"
      return
    }
    guard started == generation else { return }
    if applyConfirmedSessionBanner().blocking { return }
    do {
      let next = try await client.getState()
      let definitions = try await client.getCatalog()
      if started == generation && !busy {
        state = next
        catalog = definitions
        message = "Connected to shared Java API"
      }
    } catch is CancellationError {
      return
    } catch {
      if started == generation {
        message = "API unavailable: \(error)"
      }
    }
  }

  @discardableResult
  private func applyConfirmedSessionBanner() -> SessionBannerModel {
    guard var facts = sessionFacts else {
      let resolved = SessionBannerModel.resolve(.absent)
      banner = resolved
      return resolved
    }
    facts.now = Date()
    sessionFacts = facts
    let resolved = SessionBannerModel.resolve(.succeeded(facts))
    banner = resolved
    if resolved.blocking {
      client = nil
      state = nil
      catalog = nil
      review = false
      sessionFacts = nil
      sessionStore.clear()
      message = resolved.message
    }
    return resolved
  }

  private func pay() async {
    guard let client, !busy else { return }
    busy = true
    generation += 1
    defer { busy = false }
    do {
      let (minor, error) = parseAmount(amount)
      guard let minor else {
        message = error ?? "Invalid amount"
        return
      }
      let result = try await client.submitPayment(
        recipientId: recipient,
        amountMinor: minor,
        method: method,
        note: reference,
        scenario: .success,
        idempotencyKey: key
      )
      if result.ok {
        state = result.state
        review = false
        amount = ""
        reference = ""
        key = UUID().uuidString
        message = "Demo payment completed. Other clients will refresh."
      } else {
        message = result.error ?? "Payment pending. Retry the same payment, not a new one."
      }
    } catch {
      message = "Outcome may be unknown: \(error). Retry preserves the payment key."
    }
  }

  private func currentDeviceLabel() -> String {
    #if os(iOS)
    let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !name.isEmpty { return name }
    #elseif os(macOS)
    if let name = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
      return name
    }
    #endif
    return "This device"
  }
}
