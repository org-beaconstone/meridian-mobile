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
  @State private var clockMs = SessionBanner.nowMs()
  @State private var sessionExpiresAtMs: Int64?
  @State private var sessionActiveElsewhere = false
  @State private var extending = false

  private var sessionBanner: SessionBannerPresentation? {
    guard let sessionExpiresAtMs else { return nil }
    return SessionBanner.present(nowMs: clockMs, expiresAtMs: sessionExpiresAtMs, activeElsewhere: sessionActiveElsewhere)
  }

  private var paymentLocked: Bool { sessionBanner?.blocksInteraction == true }

  var body: some View {
    VStack(spacing: 0) {
      if let sessionBanner {
        SessionStatusBanner(
          presentation: sessionBanner,
          actionEnabled: !extending && !busy,
          onExtend: { Task { await extendSession() } },
          onReauthenticate: { Task { await reauthenticate() } }
        )
      }
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
              Picker("Recipient", selection: $recipient) { ForEach(catalog.recipients, id: \.id) { Text($0.name).tag($0.id) } }.disabled(review || busy || paymentLocked)
            }
            TextField("Amount (GBP)", text: $amount).textFieldStyle(.roundedBorder).disabled(review || busy || paymentLocked)
            TextField("Reference", text: $reference).textFieldStyle(.roundedBorder).disabled(review || busy || paymentLocked)
            // Intentionally hardcoded baseline: new providers still require a native release.
            Picker("Method", selection: $method) { Text("Debit card · Adyen").tag(PaymentMethod.card); Text("Bank payment · Worldpay").tag(PaymentMethod.bank) }.disabled(review || busy || paymentLocked)
            if review {
              Text("Confirm \(amount) GBP to \(recipient)").font(.headline)
              Button("Confirm payment") { Task { await pay() } }.buttonStyle(.borderedProminent).disabled(busy || paymentLocked)
              Button("Edit details") { review=false; key=UUID().uuidString }.disabled(busy || paymentLocked)
            } else {
              Button("Review payment") { let (value,error)=parseAmount(amount); guard value != nil else {message=error ?? "Invalid amount";return}; guard reference.count<=200 else {message="Reference is too long"; return}; key=UUID().uuidString; review=true; message="Review before confirming. No real money moves." }.disabled(busy || paymentLocked)
            }
            Text("Recent activity").font(.title2)
            ForEach(Array(state.transactions.reversed().prefix(8)), id: \.id) { transaction in HStack { VStack(alignment:.leading){Text(transaction.name);Text(transaction.provider.rawValue).font(.caption).foregroundStyle(.secondary)};Spacer();Text(money(transaction.amount)) } }
            Text("September budgets").font(.title2)
            ForEach(state.budgets, id: \.category) { budget in HStack {Text(budget.category.rawValue);Spacer();Text(money(budget.limit))} }
          }
        }.padding(24).frame(maxWidth: 550)
      }
    }.task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        clockMs = SessionBanner.nowMs()
        if !busy { await refresh() }
      }
    }
  }
  private func connect() async {
    guard room.range(of:"^[A-Za-z0-9_-]{3,64}$",options:.regularExpression) != nil else { message="Invalid room"; return }
    generation += 1; state=nil; catalog=nil; review=false; key=UUID().uuidString
    sessionActiveElsewhere = false
    do {
      client=try MeridianClient(baseURL:endpoint,sessionId:room)
      let now = SessionBanner.nowMs()
      clockMs = now
      sessionExpiresAtMs = now + SessionBanner.defaultDurationMs
      await refresh()
    } catch {
      sessionExpiresAtMs = nil
      message=String(describing:error)
    }
  }
  private func refresh() async {
    guard let client else {return}; let started=generation
    do { let next=try await client.getState(); let definitions=try await client.getCatalog(); if started==generation && !busy {state=next;catalog=definitions;message="Connected to shared Java API"} } catch { if started==generation {message="API unavailable: \(error)"} }
  }
  private func currentDraft() -> InFlightPaymentDraft {
    InFlightPaymentDraft(recipientId: recipient, amount: amount, reference: reference, method: method, reviewing: review, idempotencyKey: key)
  }
  private func extendSession() async {
    guard let client, let sessionExpiresAtMs, !extending, !busy else { return }
    guard self.sessionBanner?.extendActionLabel != nil else { return }
    let draft = currentDraft()
    let elsewhere = sessionActiveElsewhere
    let started = generation
    extending = true
    defer { extending = false }
    do {
      _ = try await client.refreshSession()
      guard started == generation else { return }
      let refreshed = SessionRefresh.extend(nowMs: SessionBanner.nowMs(), draft: draft, activeElsewhere: elsewhere)
      precondition(refreshed.draft == draft, "Session refresh must keep the in-flight payment draft")
      clockMs = SessionBanner.nowMs()
      self.sessionExpiresAtMs = refreshed.expiresAtMs
      sessionActiveElsewhere = refreshed.activeElsewhere
      message = "Connected to shared Java API"
    } catch {
      guard started == generation else { return }
      let retained = SessionRefresh.retain(nowMs: SessionBanner.nowMs(), expiresAtMs: sessionExpiresAtMs, activeElsewhere: elsewhere, draft: draft)
      self.sessionExpiresAtMs = retained.expiresAtMs
      sessionActiveElsewhere = retained.activeElsewhere
      message = "Session was not extended: \(error). Payment details and the payment key were kept."
    }
  }
  private func reauthenticate() async {
    guard let client, let sessionExpiresAtMs, !extending, !busy else { return }
    guard self.sessionBanner?.reauthenticateActionLabel != nil else { return }
    let draft = currentDraft()
    let elsewhere = sessionActiveElsewhere
    let started = generation
    extending = true
    defer { extending = false }
    do {
      _ = try await client.refreshSession()
      guard started == generation else { return }
      let refreshed = SessionRefresh.reauthenticate(nowMs: SessionBanner.nowMs(), draft: draft)
      precondition(refreshed.draft == draft, "Session refresh must keep the in-flight payment draft")
      clockMs = SessionBanner.nowMs()
      self.sessionExpiresAtMs = refreshed.expiresAtMs
      sessionActiveElsewhere = refreshed.activeElsewhere
      message = "Connected to shared Java API"
    } catch {
      guard started == generation else { return }
      let retained = SessionRefresh.retain(nowMs: SessionBanner.nowMs(), expiresAtMs: sessionExpiresAtMs, activeElsewhere: elsewhere, draft: draft)
      self.sessionExpiresAtMs = retained.expiresAtMs
      sessionActiveElsewhere = retained.activeElsewhere
      message = "Re-authentication failed: \(error). Payment details and the payment key were kept."
    }
  }
  private func pay() async {
    guard let client, !busy, !paymentLocked else {return}; busy=true; generation += 1
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
