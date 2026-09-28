import SwiftUI
import MeridianSDK

@main struct MeridianApp: App {
  var body: some Scene { WindowGroup { MeridianView().frame(minWidth: 350, minHeight: 650) } }
}
@MainActor struct MeridianView: View {
  @State private var endpoint = "http://127.0.0.1:8080/api/v1"
  @State private var room = "meridian-rehearsal"
  @State private var client: MeridianClient?
  @State private var rehearsal: RehearsalSession?
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
          if review {
            Text("Confirm \(amount) GBP to \(recipient)").font(.headline)
            Button("Confirm payment") { Task { await pay() } }.buttonStyle(.borderedProminent).disabled(busy)
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
    }.task {
      while !Task.isCancelled { try? await Task.sleep(for: .seconds(2)); if !busy { await refresh() } }
    }
  }
  private func connect() async {
    guard room.range(of:"^[A-Za-z0-9_-]{3,64}$",options:.regularExpression) != nil else { message="Invalid room"; return }
    generation += 1; state=nil; catalog=nil; review=false; key=UUID().uuidString; client=nil; rehearsal=nil
    do {
      let next=try MeridianClient(baseURL:endpoint,sessionId:room)
      client=next
      rehearsal=RehearsalSession(client:next)
      await refresh()
    } catch { message=String(describing:error) }
  }
  private func refresh() async {
    guard let client, let rehearsal else {return}
    let started=generation
    var stateError: String?
    do {
      let next=try await client.getState()
      if started==generation && !busy { state=next }
    } catch { stateError=String(describing:error) }
    let hydration=await rehearsal.hydrateCatalog()
    guard started==generation && !busy else { return }
    if let definitions=hydration.catalog { catalog=definitions }
    if hydration.degraded {
      message = hydration.catalog == nil ? "API unavailable and no catalog has been loaded" : "Showing last-known-good catalog"
    } else if let stateError {
      message="API unavailable: \(stateError)"
    } else {
      message="Connected to shared Java API"
    }
  }
  private func pay() async {
    guard let rehearsal, !busy else {return}
    busy=true; generation += 1
    defer {busy=false}
    let (minor,error)=parseAmount(amount)
    guard let minor else {message=error ?? "Invalid amount";return}
    let attempt=PaymentAttempt(recipientId:recipient,amountMinor:minor,method:method,note:reference,scenario:.success,idempotencyKey:key)
    switch await rehearsal.submit(attempt) {
    case let .settled(response, _):
      state=response.state; review=false; amount=""; reference=""; key=UUID().uuidString
      message="Demo payment completed. Other clients will refresh."
    case let .pending(response, kept):
      key=kept.idempotencyKey
      message=response.error ?? "Payment pending confirmation. Retry the same payment, not a new one."
    case let .declined(response, kept):
      key=kept.idempotencyKey
      message=response.error ?? "Payment declined. No debit was made."
    case let .retryable(text, kept):
      key=kept.idempotencyKey
      method=kept.method
      message="\(text) Retry keeps the same payment key and selected method."
    case let .rejected(text, kept):
      key=kept.idempotencyKey
      message=text
    }
  }
}
