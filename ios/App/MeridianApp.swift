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
  @State private var sessionPresence: SessionPresence = .signedOut
  @State private var sessionExpiresAt = Date(timeIntervalSince1970: 0)
  @State private var now = Date()

  private var phase: SessionPhase {
    sessionPhase(presence: sessionPresence, expiresAt: sessionExpiresAt, now: now)
  }

  private var sessionAllowsPayment: Bool {
    if case .banner(let banner) = phase { return banner != .signedOut }
    return false
  }

  var body: some View {
    VStack(spacing: 0) {
      if case .banner(let banner) = phase {
        SessionStatusBanner(state: banner, remaining: sessionExpiresAt.timeIntervalSince(now)) {
          Task { await applySessionRefresh() }
        }
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("meridian").font(.largeTitle).fontWeight(.semibold)
          Text("Native SwiftUI · Fictional payment rehearsal").font(.caption)
          Group {
            TextField("API base URL", text: $endpoint)
            TextField("Shared rehearsal room", text: $room)
            Button("Connect") { Task { await connect() } }.disabled(busy)
            Text("Session").font(.caption)
            Picker("Session", selection: Binding(get: { sessionPresence }, set: { applyPresence($0) })) {
              Text("This device").tag(SessionPresence.here)
              Text("Another device").tag(SessionPresence.elsewhere)
              Text("Signed out").tag(SessionPresence.signedOut)
            }
            .pickerStyle(.segmented)
            Button("End session") {
              sessionPresence = .here
              sessionExpiresAt = Date().addingTimeInterval(-1)
              now = Date()
            }
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
            if review {
              Text("Confirm \(amount) GBP to \(recipient)").font(.headline)
              Button("Confirm payment") { Task { await pay() } }.buttonStyle(.borderedProminent).disabled(busy || !sessionAllowsPayment)
              Button("Edit details") { review=false; key=UUID().uuidString }.disabled(busy)
            } else {
              Button("Review payment") { let (value,error)=parseAmount(amount); guard value != nil else {message=error ?? "Invalid amount";return}; guard reference.count<=200 else {message="Reference is too long"; return}; key=UUID().uuidString; review=true; message="Review before confirming. No real money moves." }.disabled(busy)
            }
            Text("Recent activity").font(.title2)
            ForEach(Array(state.transactions.reversed().prefix(8)), id: \.id) { transaction in HStack { VStack(alignment:.leading){Text(transaction.name);Text(transaction.provider.rawValue).font(.caption).foregroundStyle(.secondary)};Spacer();Text(money(transaction.amount)) } }
            Text("September budgets").font(.title2)
            ForEach(state.budgets, id: \.category) { budget in HStack {Text(budget.category.rawValue);Spacer();Text(money(budget.limit))} }
          }
        }.padding(24).frame(maxWidth: 550)
      }
    }
    .alert(
      "Session expired",
      isPresented: Binding(
        get: { sessionRequiresReauthentication(presence: sessionPresence, expiresAt: sessionExpiresAt, now: now) },
        set: { _ in }
      )
    ) {
      Button("Sign in again") { Task { await applySessionRefresh() } }
    } message: {
      Text("Sign in again to continue this payment. Entered details stay on this screen.")
    }
    .task {
      while !Task.isCancelled { try? await Task.sleep(for: .seconds(2)); if !busy { await refresh() } }
    }
    .task {
      while !Task.isCancelled {
        now = Date()
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }
  private func connect() async {
    guard room.range(of:"^[A-Za-z0-9_-]{3,64}$",options:.regularExpression) != nil else { message="Invalid room"; return }
    generation += 1; state=nil; catalog=nil; review=false; key=UUID().uuidString
    do {
      client=try MeridianClient(baseURL:endpoint,sessionId:room)
      sessionPresence = .here
      sessionExpiresAt = Date().addingTimeInterval(paymentSessionTtl)
      now = Date()
      await refresh()
    } catch { message=String(describing:error) }
  }
  private func refresh() async {
    guard let client else {return}; let started=generation
    do { let next=try await client.getState(); let definitions=try await client.getCatalog(); if started==generation && !busy {state=next;catalog=definitions;message="Connected to shared Java API"} } catch { if started==generation {message="API unavailable: \(error)"} }
  }
  private func applyPresence(_ presence: SessionPresence) {
    switch presence {
    case .signedOut:
      sessionPresence = .signedOut
    case .here:
      Task { await applySessionRefresh() }
    case .elsewhere:
      if sessionPresence == .signedOut || now >= sessionExpiresAt {
        Task {
          await applySessionRefresh()
          sessionPresence = .elsewhere
        }
      } else {
        sessionPresence = .elsewhere
      }
    }
  }
  private func applySessionRefresh() async {
    if client == nil && room.range(of: "^[A-Za-z0-9_-]{3,64}$", options: .regularExpression) == nil {
      message = "Invalid room"
      return
    }
    let refreshed = refreshSessionInPlace(
      draft: PaymentFormDraft(
        recipientId: recipient,
        amount: amount,
        reference: reference,
        method: method,
        reviewing: review,
        idempotencyKey: key
      ),
      session: PaymentSessionClock(presence: sessionPresence, expiresAt: sessionExpiresAt),
      now: Date()
    )
    recipient = refreshed.draft.recipientId
    amount = refreshed.draft.amount
    reference = refreshed.draft.reference
    method = refreshed.draft.method
    review = refreshed.draft.reviewing
    key = refreshed.draft.idempotencyKey
    sessionPresence = refreshed.session.presence
    sessionExpiresAt = refreshed.session.expiresAt
    now = Date()
    if client == nil {
      do {
        client = try MeridianClient(baseURL: endpoint, sessionId: room)
        await refresh()
      } catch {
        message = String(describing: error)
        return
      }
    }
    message = "Session refreshed. Payment details are unchanged."
  }
  private func pay() async {
    guard let client, !busy else {return}
    guard sessionAllowsPayment else {
      message = "Restore the session before confirming this payment."
      return
    }
    busy=true; generation += 1
    defer {busy=false}
    do {
      let (minor,error)=parseAmount(amount)
      guard let minor else {message=error ?? "Invalid amount";return}
      let result=try await client.submitPayment(recipientId:recipient,amountMinor:minor,method:method,note:reference,scenario:.success,idempotencyKey:key)
      if result.ok {state=result.state;review=false;amount="";reference="";key=UUID().uuidString;message="Demo payment completed. Other clients will refresh."}
      else {message=result.error ?? "Payment pending. Retry the same payment, not a new one."}
    } catch {message="Outcome may be unknown: \(error). Retry preserves the payment key."}
  }
}
