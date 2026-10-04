import SwiftUI
import MeridianSDK

@main struct MeridianApp: App {
  var body: some Scene { WindowGroup { MeridianView().frame(minWidth: 350, minHeight: 650) } }
}

private struct HeldPayment: Equatable {
  let key: String
  let recipientId: String
  let amountMinor: Int
  let method: PaymentMethod
  let note: String
}

@MainActor struct MeridianView: View {
  @State private var endpoint = "http://127.0.0.1:8080/api/v1"
  @State private var room = "meridian-rehearsal"
  @State private var connectedRoom = ""
  @State private var client: MeridianClient?
  @State private var state: BankState?
  @State private var catalog: CatalogResponse?
  @State private var health: SessionHealth?
  @State private var recipient = "northline-studio"
  @State private var amount = ""
  @State private var reference = ""
  @State private var method: PaymentMethod = .card
  @State private var key = UUID().uuidString
  @State private var held: HeldPayment?
  @State private var review = false
  @State private var busy = false
  @State private var message = "Connect to the Spring Boot API to start."
  @State private var retryBanner: String?
  @State private var generation = 0
  @State private var sessionToken = 0

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("meridian").font(.largeTitle).fontWeight(.semibold)
        Text("Native SwiftUI · Fictional payment rehearsal").font(.caption)
        Group {
          TextField("API base URL", text: $endpoint)
          TextField("Shared rehearsal room", text: $room)
          Button("Connect") { Task { await connect() } }.disabled(busy)
        }.textFieldStyle(.roundedBorder)
        Text(message).font(.callout).foregroundStyle(.secondary)
        if let retryBanner {
          VStack(alignment: .leading, spacing: 8) {
            Text(retryBanner).font(.callout)
            Button("Retry payment") { Task { await retryHeld() } }
              .buttonStyle(.borderedProminent)
              .disabled(busy)
          }
          .padding(14)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(red: 1, green: 0.929, blue: 0.922))
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .accessibilityElement(children: .contain)
        }
        if let notice = health.flatMap({ corridorNotice(for: $0, selected: method) }) {
          corridorBanner(notice)
        }
        if let state {
          VStack(alignment: .leading, spacing: 8) {
            Text("Everyday account · GBP").font(.caption)
            Text(money(state.balance)).font(.system(size: 38, weight: .medium))
            Text("Shared room: \(room)").font(.caption)
          }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Color(red:0.078,green:0.173,blue:0.208)).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 16))
          Text("Make a payment").font(.title2)
          if let catalog {
            Picker("Recipient", selection: $recipient) { ForEach(catalog.recipients, id: \.id) { Text($0.name).tag($0.id) } }.disabled(review || busy)
          }
          TextField("Amount (GBP)", text: $amount).textFieldStyle(.roundedBorder).disabled(review || busy)
          TextField("Reference", text: $reference).textFieldStyle(.roundedBorder).disabled(review || busy)
          // Intentionally hardcoded baseline: new providers still require a native release.
          Picker("Method", selection: $method) { Text("Debit card · Adyen").tag(PaymentMethod.card); Text("Bank payment · Worldpay").tag(PaymentMethod.bank) }.disabled(review || busy)
          if review {
            Text("Confirm \(amount) GBP to \(recipient)").font(.headline)
            Button("Confirm payment") { Task { await pay() } }.buttonStyle(.borderedProminent).disabled(busy)
            Button("Edit details") { review = false; if held == nil { key = UUID().uuidString } }.disabled(busy)
          } else {
            Button("Review payment") {
              let (value, error) = parseAmount(amount)
              guard value != nil else { message = error ?? "Invalid amount"; return }
              guard reference.count <= 200 else { message = "Reference is too long"; return }
              if held == nil { key = UUID().uuidString }
              review = true
              message = "Review before confirming. No real money moves."
            }.disabled(busy)
          }
          Text("Recent activity").font(.title2)
          ForEach(Array(state.transactions.reversed().prefix(8)), id: \.id) { transaction in HStack { VStack(alignment:.leading){Text(transaction.name);Text(transaction.provider.rawValue).font(.caption).foregroundStyle(.secondary)};Spacer();Text(money(transaction.amount)) } }
          Text("September budgets").font(.title2)
          ForEach(state.budgets, id: \.category) { budget in HStack {Text(budget.category.rawValue);Spacer();Text(money(budget.limit))} }
        }
      }.padding(24).frame(maxWidth: 550)
    }
    .task {
      while !Task.isCancelled { try? await Task.sleep(for: .seconds(2)); if !busy { await refresh() } }
    }
    .task(id: sessionToken) {
      guard let client else { return }
      let updates = await client.pollSessionHealth(every: .seconds(5))
      for await snapshot in updates {
        health = snapshot.health
      }
    }
  }

  @ViewBuilder private func corridorBanner(_ notice: CorridorNotice) -> some View {
    switch notice {
    case let .switchRail(prompt):
      VStack(alignment: .leading, spacing: 8) {
        Text("\(railLabel(prompt.selectedMethod)) is \(prompt.reason) in corridor \(prompt.corridorId). \(railLabel(prompt.alternateMethod)) is eligible. Choosing it does not send the payment.")
          .font(.callout)
        Button(prompt.alternateMethod == .card ? "Use debit card" : "Use bank payment") {
          useAlternate(prompt.alternateMethod)
        }
        .disabled(busy)
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(red: 1, green: 0.969, blue: 0.902))
      .clipShape(RoundedRectangle(cornerRadius: 8))
    case let .unavailable(_, text):
      Text(text)
        .font(.callout)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 1, green: 0.969, blue: 0.902))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
  }

  private func useAlternate(_ next: PaymentMethod) {
    if let held, key == held.key { key = UUID().uuidString }
    method = next
  }

  private func keyForSubmit(minor: Int) -> String {
    if let held, held.method == method, held.recipientId == recipient, held.note == reference, held.amountMinor == minor {
      return held.key
    }
    if let held, key == held.key { key = UUID().uuidString }
    return key
  }

  private func rememberAttempt(minor: Int, activeKey: String) {
    held = HeldPayment(key: activeKey, recipientId: recipient, amountMinor: minor, method: method, note: reference)
  }

  private func connect() async {
    guard room.range(of: "^[A-Za-z0-9_-]{3,64}$", options: .regularExpression) != nil else { message = "Invalid room"; return }
    let switching = !connectedRoom.isEmpty && connectedRoom != room
    generation += 1
    if switching {
      state = nil
      catalog = nil
      review = false
      held = nil
      retryBanner = nil
      health = nil
      key = UUID().uuidString
    }
    connectedRoom = room
    do {
      await client?.stopSessionHealthPolling()
      client = try MeridianClient(baseURL: endpoint, sessionId: room)
      sessionToken += 1
      await refresh()
    } catch {
      message = String(describing: error)
    }
  }

  private func refresh() async {
    guard let client else { return }
    let started = generation
    do {
      let next = try await client.getState()
      let definitions = try await client.getCatalog()
      if started == generation && !busy {
        state = next
        catalog = definitions
        message = "Connected to shared Java API"
      }
    } catch {
      if started == generation {
        message = state == nil
          ? "API unavailable: \(error)"
          : "Connection interrupted. Payment details are still here."
      }
    }
  }

  private func retryHeld() async {
    guard let client, let held, !busy else { return }
    busy = true
    generation += 1
    defer { busy = false }
    do {
      let result = try await client.submitPayment(
        recipientId: held.recipientId,
        amountMinor: held.amountMinor,
        method: held.method,
        note: held.note,
        scenario: .success,
        idempotencyKey: held.key
      )
      if result.ok {
        state = result.state
        let (minor, _) = parseAmount(amount)
        if method == held.method && recipient == held.recipientId && reference == held.note && minor == held.amountMinor {
          review = false
          amount = ""
          reference = ""
          key = UUID().uuidString
        }
        self.held = nil
        retryBanner = nil
        message = "Demo payment completed. Other clients will refresh."
      } else {
        retryBanner = result.error ?? "Payment is unresolved. Retry uses the same payment key."
        message = "Payment details are unchanged."
      }
    } catch let failure as MeridianError {
      retryBanner = failure.errorDescription ?? "Outcome may be unknown. Retry uses the same payment key."
      message = "Payment details are unchanged."
    } catch {
      retryBanner = "Outcome may be unknown. Retry uses the same payment key."
      message = "Payment details are unchanged."
    }
  }

  private func pay() async {
    guard let client, !busy else { return }
    busy = true
    generation += 1
    defer { busy = false }
    let (minor, error) = parseAmount(amount)
    guard let minor else { message = error ?? "Invalid amount"; return }
    let activeKey = keyForSubmit(minor: minor)
    let activeMethod = method
    do {
      let result = try await client.submitPayment(
        recipientId: recipient,
        amountMinor: minor,
        method: activeMethod,
        note: reference,
        scenario: .success,
        idempotencyKey: activeKey
      )
      if result.ok {
        state = result.state
        review = false
        amount = ""
        reference = ""
        key = UUID().uuidString
        held = nil
        retryBanner = nil
        message = "Demo payment completed. Other clients will refresh."
      } else {
        rememberAttempt(minor: minor, activeKey: activeKey)
        retryBanner = result.error ?? "Payment is unresolved. Retry uses the same payment key."
        message = "Payment details are unchanged."
      }
    } catch let failure as MeridianError {
      rememberAttempt(minor: minor, activeKey: activeKey)
      retryBanner = failure.errorDescription ?? "Outcome may be unknown. Retry uses the same payment key."
      message = "Payment details are unchanged."
    } catch {
      rememberAttempt(minor: minor, activeKey: activeKey)
      retryBanner = "Outcome may be unknown. Retry uses the same payment key."
      message = "Payment details are unchanged."
    }
  }
}
