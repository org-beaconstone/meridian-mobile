import SwiftUI
import MeridianSDK

@main struct MeridianApp: App {
  var body: some Scene { WindowGroup { MeridianView().frame(minWidth: 350, minHeight: 650) } }
}

@MainActor struct MeridianView: View {
  @State private var endpoint = "http://127.0.0.1:8080/api/v1"
  @State private var room = "meridian-rehearsal"
  @State private var connectedRoom = "meridian-rehearsal"
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
  @State private var vault = ReturnStateVault()
  @State private var attempt: PaymentAttempt?
  @State private var handoff: IssuedBankHandoff?
  @State private var pin = ""
  @State private var pinRepeat = ""
  @State private var pastedReturn = ""

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
          checkout
          Text("Recent activity").font(.title2)
          ForEach(Array(state.transactions.reversed().prefix(8)), id: \.id) { transaction in HStack { VStack(alignment:.leading){Text(transaction.name);Text(transaction.provider.rawValue).font(.caption).foregroundStyle(.secondary)};Spacer();Text(money(transaction.amount)) } }
          Text("September budgets").font(.title2)
          ForEach(state.budgets, id: \.category) { budget in HStack {Text(budget.category.rawValue);Spacer();Text(money(budget.limit))} }
        }
      }.padding(24).frame(maxWidth: 550)
    }.task {
      while !Task.isCancelled { try? await Task.sleep(for: .seconds(2)); if !busy { await refresh() } }
    }.onOpenURL { url in
      handleReturn(url.absoluteString)
    }
  }

  @ViewBuilder private var checkout: some View {
    if review && method == .card && attempt != nil && attempt?.readyToSubmit != true {
      scaChallenge
    } else if review && method == .bank && handoff != nil && attempt?.readyToSubmit != true {
      bankHandoff
    } else if review && attempt?.readyToSubmit == true {
      Text("Authentication is in place. Retry keeps payment key \(key).").font(.caption)
      Button("Retry same payment") { Task { await pay() } }.buttonStyle(.borderedProminent).disabled(busy)
      Button("Edit details") { editDetails() }.disabled(busy)
    } else if review {
      Text("Confirm \(amount) GBP to \(recipient)").font(.headline)
      Button(method == .card ? "Continue to authentication" : "Continue to your bank") { beginAuthentication() }
        .buttonStyle(.borderedProminent).disabled(busy)
      Button("Edit details") { editDetails() }.disabled(busy)
    } else {
      Button("Review payment") { reviewPayment() }.disabled(busy)
    }
  }

  private var scaChallenge: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Strong Customer Authentication").font(.headline)
      Text("Confirm with biometrics or device PIN, or enter a 4–6 digit app PIN. The PIN is checked on this device and is not sent anywhere.")
        .font(.caption)
      Button("Confirm with biometrics or device PIN") {
        DeviceOwnerConfirmation.evaluate(reason: "Confirm this rehearsal payment") { success in
          if success {
            attempt = attempt?.confirmingBiometric(succeeded: true)
            Task { await pay() }
          } else {
            message = "Device authentication was not confirmed. The payment was not sent. You can try again or use a PIN."
          }
        }
      }.disabled(busy)
      SecureField("App PIN", text: $pin)
      SecureField("Repeat app PIN", text: $pinRepeat)
      Button("Confirm with PIN") { confirmPin() }.disabled(busy)
      Button("Back") {
        attempt = nil
        pin = ""
        pinRepeat = ""
        message = "Authentication cancelled. The payment was not sent and the payment key was kept."
      }.disabled(busy)
    }
  }

  private var bankHandoff: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Bank handoff").font(.headline)
      Text("Opens only https://\(BankHandoffPolicy.bankHost). This rehearsal link does not contact a live bank. The return is checked before any payment.")
        .font(.caption)
      Button("Open bank handoff") {
        guard let handoff else { return }
        if !BankHandoffOpener.openIfAllowlisted(handoff.handoffURL) {
          message = "This device did not open the allowlisted handoff. Apply the return link below. The payment has not been sent."
        }
      }.disabled(busy)
      if let handoff {
        Text(handoff.returnURL).font(.caption).textSelection(.enabled)
      }
      TextField("Return link", text: $pastedReturn).textFieldStyle(.roundedBorder)
      Button("Apply return link") {
        let link = pastedReturn.isEmpty ? (handoff?.returnURL ?? "") : pastedReturn
        if !link.isEmpty { handleReturn(link) }
      }.disabled(busy)
      Button("Cancel handoff") {
        if let handoff { vault.cancel(state: handoff.state) }
        self.handoff = nil
        attempt = nil
        message = "Bank handoff cancelled. The payment was not sent and the payment key was kept."
      }.disabled(busy)
    }
  }

  private func reviewPayment() {
    let (value, error) = parseAmount(amount)
    guard value != nil else { message = error ?? "Invalid amount"; return }
    guard reference.count <= 200 else { message = "Reference is too long"; return }
    clearHandoff(rotateKey: true)
    review = true
    message = "Review before confirming. No real money moves."
  }

  private func editDetails() {
    clearHandoff(rotateKey: true)
    review = false
  }

  private func beginAuthentication() {
    attempt = PaymentAttempt(idempotencyKey: key, method: method)
    pin = ""
    pinRepeat = ""
    if method == .card {
      message = "Use biometrics, device PIN, or an app PIN. Nothing is sent until that succeeds."
      return
    }
    do {
      let issued = try vault.issue(sessionId: connectedRoom, paymentKey: key)
      handoff = issued
      let opened = BankHandoffOpener.openIfAllowlisted(issued.handoffURL)
      message = opened
        ? "Opened the allowlisted rehearsal bank handoff. The payment waits for a valid return."
        : "Rehearsal bank handoff is ready, but this device did not open it. Apply the return link below. The payment has not been sent."
    } catch {
      handoff = nil
      message = "Could not start the bank handoff. The payment was not sent and the payment key was kept."
    }
  }

  private func confirmPin() {
    guard let current = attempt else { return }
    let (updated, error) = current.confirmingPin(pin: pin, repeated: pinRepeat)
    pin = ""
    pinRepeat = ""
    attempt = updated
    if let error {
      message = "\(error) The payment was not sent."
    } else {
      Task { await pay() }
    }
  }

  private func handleReturn(_ url: String) {
    let decision = vault.intercept(url: url, expectedSession: connectedRoom, expectedPaymentKey: key)
    let waiting = method == .bank && review && handoff != nil
    guard waiting else {
      if decision.outcome != .ignored {
        message = decision.outcome == .accepted
          ? "Bank return was not applied. The payment was not sent."
          : decision.outcome.userMessage
      }
      return
    }
    let before = attempt?.bankAccepted == true
    let updated = (attempt ?? PaymentAttempt(idempotencyKey: key, method: .bank)).applying(decision)
    attempt = updated
    if !before && updated.bankAccepted {
      Task { await pay() }
    } else if decision.outcome != .accepted {
      message = decision.outcome.userMessage
    }
  }

  private func clearHandoff(rotateKey: Bool) {
    if let handoff { vault.cancel(state: handoff.state) }
    handoff = nil
    attempt = nil
    pin = ""
    pinRepeat = ""
    pastedReturn = ""
    if rotateKey { key = UUID().uuidString }
  }

  private func connect() async {
    guard room.range(of:"^[A-Za-z0-9_-]{3,64}$",options:.regularExpression) != nil else { message="Invalid room"; return }
    generation += 1
    state = nil
    catalog = nil
    review = false
    vault = ReturnStateVault()
    clearHandoff(rotateKey: true)
    do {
      client = try MeridianClient(baseURL: endpoint, sessionId: room)
      connectedRoom = room
      await refresh()
    } catch { message = String(describing: error) }
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
        if !review { message = "Connected to shared Java API" }
      }
    } catch {
      if started == generation { message = "API unavailable: \(error)" }
    }
  }

  private func pay() async {
    guard let client, !busy else { return }
    guard let attempt, attempt.readyToSubmit, attempt.idempotencyKey == key else {
      message = "Authentication is still required. The payment was not sent."
      return
    }
    busy = true
    generation += 1
    defer { busy = false }
    do {
      let (minor, error) = parseAmount(amount)
      guard let minor else { message = error ?? "Invalid amount"; return }
      let result = try await client.submitPayment(
        recipientId: recipient,
        amountMinor: minor,
        method: method,
        note: reference,
        scenario: .success,
        idempotencyKey: attempt.idempotencyKey
      )
      if result.ok {
        state = result.state
        review = false
        amount = ""
        reference = ""
        self.attempt = nil
        handoff = nil
        key = UUID().uuidString
        message = "Demo payment completed. Other clients will refresh."
      } else {
        message = (result.error ?? "Payment pending. Retry the same payment, not a new one.") + " Payment key kept."
      }
    } catch {
      message = "Outcome may be unknown: \(error). Retry preserves the payment key."
    }
  }
}
