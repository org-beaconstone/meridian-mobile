import SwiftUI
import MeridianSDK

@main struct MeridianApp: App {
  var body: some Scene { WindowGroup { MeridianView().frame(minWidth: 350, minHeight: 650) } }
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
  @State private var sessionExpiresAtMs: Int64?
  @State private var sessionElsewhere = false
  @State private var sessionProbe: SessionProbeResult = .notSignedIn
  @State private var nowMs = SessionBanner.nowMs()
  @State private var refreshingSession = false

  private var paymentContext: PaymentContext {
    PaymentContext(
      recipientId: recipient,
      amount: amount,
      reference: reference,
      method: method,
      reviewing: review,
      idempotencyKey: key
    )
  }

  private var sessionClock: SessionClock {
    SessionClock(
      sessionId: client == nil ? nil : room,
      expiresAtMs: sessionExpiresAtMs,
      activeElsewhere: sessionElsewhere,
      probe: client == nil ? .notSignedIn : sessionProbe
    )
  }

  private var banner: SessionBannerPresentation {
    SessionBanner.present(nowMs: nowMs, clock: sessionClock)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("meridian").font(.largeTitle).fontWeight(.semibold)
        Text("Native SwiftUI · Fictional payment rehearsal").font(.caption)
        SessionStatusBanner(presentation: banner, refreshing: refreshingSession) {
          Task { await performBannerAction() }
        }
        Group {
          TextField("API base URL", text: $endpoint)
            .accessibilityIdentifier(SessionAccessibility.endpoint)
          TextField("Shared rehearsal room", text: $room)
            .accessibilityIdentifier(SessionAccessibility.room)
          Button("Connect") { Task { await connect() } }
            .disabled(busy)
            .accessibilityIdentifier(SessionAccessibility.connect)
        }.textFieldStyle(.roundedBorder)
        Text(message).font(.callout).foregroundStyle(.secondary)
        if let state {
          VStack(alignment: .leading, spacing: 8) {
            Text("Everyday account · GBP").font(.caption)
            Text(money(state.balance)).font(.system(size: 38, weight: .medium))
            Text("Shared room: \(room)").font(.caption)
          }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Color(red:0.078,green:0.173,blue:0.208)).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 16))
          VStack(alignment: .leading, spacing: 18) {
            Text("Make a payment").font(.title2)
            if let catalog {
              Picker("Recipient", selection: $recipient) { ForEach(catalog.recipients, id: \.id) { Text($0.name).tag($0.id) } }.disabled(review || busy || banner.blocksPaymentEntry)
            }
            TextField("Amount (GBP)", text: $amount).textFieldStyle(.roundedBorder).disabled(review || busy || banner.blocksPaymentEntry)
            TextField("Reference", text: $reference).textFieldStyle(.roundedBorder).disabled(review || busy || banner.blocksPaymentEntry)
            // Intentionally hardcoded baseline: new providers still require a native release.
            Picker("Method", selection: $method) { Text("Debit card · Adyen").tag(PaymentMethod.card); Text("Bank payment · Worldpay").tag(PaymentMethod.bank) }.disabled(review || busy || banner.blocksPaymentEntry)
            if review {
              Text("Confirm \(amount) GBP to \(recipient)").font(.headline)
              Button("Confirm payment") { Task { await pay() } }.buttonStyle(.borderedProminent).disabled(busy || banner.blocksPaymentEntry)
              Button("Edit details") { review=false; key=UUID().uuidString }.disabled(busy || banner.blocksPaymentEntry)
            } else {
              Button("Review payment") { let (value,error)=parseAmount(amount); guard value != nil else {message=error ?? "Invalid amount";return}; guard reference.count<=200 else {message="Reference is too long"; return}; key=UUID().uuidString; review=true; message="Review before confirming. No real money moves." }.disabled(busy || banner.blocksPaymentEntry)
            }
            Text("Recent activity").font(.title2)
            ForEach(Array(state.transactions.reversed().prefix(8)), id: \.id) { transaction in HStack { VStack(alignment:.leading){Text(transaction.name);Text(transaction.provider.rawValue).font(.caption).foregroundStyle(.secondary)};Spacer();Text(money(transaction.amount)) } }
            Text("September budgets").font(.title2)
            ForEach(state.budgets, id: \.category) { budget in HStack {Text(budget.category.rawValue);Spacer();Text(money(budget.limit))} }
          }
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier(SessionAccessibility.paymentForm)
        }
      }.padding(24).frame(maxWidth: 550)
    }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        nowMs = SessionBanner.nowMs()
      }
    }
    .task {
      while !Task.isCancelled { try? await Task.sleep(for: .seconds(2)); if !busy { await refresh() } }
    }
  }

  private func performBannerAction() async {
    switch banner.state {
    case .signedOut:
      await connect(preservingPaymentContext: true)
    case .expiring, .expired, .unknown:
      await extendCurrentSession()
    case .active, .activeElsewhere:
      break
    }
  }

  /// Session recovery updates the clock only. Amount, recipient, reference, method, review, and the payment key stay as entered.
  private func extendCurrentSession() async {
    guard let client, !refreshingSession else { return }
    refreshingSession = true
    defer { refreshingSession = false }
    let clock = sessionClock
    do {
      let payload = try await client.refreshSession()
      let updated = SessionActions.refresh(
        nowMs: SessionBanner.nowMs(),
        clock: clock,
        context: paymentContext,
        activeElsewhere: payload.activeElsewhere
      )
      applyClock(updated.clock)
    } catch {
      let updated = SessionActions.noteFailure(
        clock: clock,
        context: paymentContext,
        failure: classify(error)
      )
      applyClock(updated.clock)
    }
  }

  private func applyClock(_ clock: SessionClock) {
    sessionExpiresAtMs = clock.expiresAtMs
    sessionElsewhere = clock.activeElsewhere
    sessionProbe = clock.probe
  }

  private func connect(preservingPaymentContext: Bool = false) async {
    let kept = paymentContext
    guard room.range(of:"^[A-Za-z0-9_-]{3,64}$",options:.regularExpression) != nil else { message="Invalid room"; return }
    generation += 1
    if !preservingPaymentContext {
      state=nil
      catalog=nil
      review=false
      key=UUID().uuidString
    }
    do {
      client=try MeridianClient(baseURL:endpoint,sessionId:room)
      let signedIn = SessionActions.signIn(
        nowMs: SessionBanner.nowMs(),
        sessionId: room,
        context: preservingPaymentContext ? kept : paymentContext
      )
      applyClock(signedIn.clock)
      await refresh()
    } catch {
      message=String(describing:error)
    }
  }

  private func refresh() async {
    guard let client else {return}
    let started=generation
    do {
      let next=try await client.getState()
      let definitions=try await client.getCatalog()
      if started==generation && !busy && !refreshingSession {
        state=next
        catalog=definitions
        message="Connected to shared Java API"
        if sessionProbe != .rejected { sessionProbe = .confirmed }
      }
    } catch {
      if started==generation && !refreshingSession {
        message="API unavailable: \(error)"
        let updated = SessionActions.noteFailure(clock: sessionClock, context: paymentContext, failure: classify(error))
        applyClock(updated.clock)
      }
    }
  }

  private func pay() async {
    guard let client, !busy else {return}
    busy=true
    generation += 1
    defer {busy=false}
    do {
      let (minor,error)=parseAmount(amount)
      guard let minor else {message=error ?? "Invalid amount";return}
      let result=try await client.submitPayment(recipientId:recipient,amountMinor:minor,method:method,note:reference,scenario:.success,idempotencyKey:key)
      if result.ok {state=result.state;review=false;amount="";reference="";key=UUID().uuidString;message="Demo payment completed. Other clients will refresh."}
      else {message=result.error ?? "Payment pending. Retry the same payment, not a new one."}
    } catch {message="Outcome may be unknown: \(error). Retry preserves the payment key."}
  }

  private func classify(_ error: Error) -> SessionFailure {
    if case let MeridianError.httpError(code, _) = error {
      return SessionActions.classify(statusCode: code, timedOut: false)
    }
    if let urlError = error as? URLError, urlError.code == .timedOut {
      return .timeout
    }
    let text = String(describing: error).lowercased()
    if text.contains("timed out") || text.contains("timeout") {
      return .timeout
    }
    return .other
  }
}
