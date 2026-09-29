import SwiftUI
import MeridianSDK

@main struct MeridianApp: App {
  var body: some Scene { WindowGroup { MeridianView().frame(minWidth: 350, minHeight: 650) } }
}
@MainActor struct MeridianView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var endpoint = "http://127.0.0.1:8080/api/v1"
  @State private var room = "meridian-rehearsal"
  @State private var client: MeridianClient?
  @State private var state: BankState?
  @State private var catalog: CatalogResponse?
  @State private var recipient = "northline-studio"
  @State private var amount = ""
  @State private var reference = ""
  @State private var method: PaymentMethod = .card
  @State private var showMethods = false
  @State private var key = UUID().uuidString
  @State private var review = false
  @State private var busy = false
  @State private var message = "Connect to the Spring Boot API to start."
  @State private var generation = 0
  private var rails: [PaymentMethodOption]? { catalog.map { resolvePaymentRails(from: $0.providers) } }
  private var methodLabel: String {
    if catalog == nil { return "Loading payment methods…" }
    if let selected = rails?.first(where: { $0.method == method }) { return selected.badge }
    return method == .card ? "Debit card · Adyen" : "Bank payment · Worldpay"
  }
  private var selectedRailAvailable: Bool { rails?.first(where: { $0.method == method })?.available == true }
  var body: some View {
    ZStack(alignment: .bottom) {
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
          Button { showMethods = true } label: {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text("Payment method").font(.caption).foregroundStyle(.secondary)
                Text(methodLabel)
              }
              Spacer()
              Image(systemName: "chevron.up").accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.35)))
          }
          .buttonStyle(.plain)
          .disabled(review || busy)
          .accessibilityLabel("Payment method")
          .accessibilityValue(methodLabel)
          .accessibilityHint("Opens the payment method sheet")
          if review {
            Text("Confirm \(amount) GBP to \(recipient)").font(.headline)
            if !selectedRailAvailable { Text(PaymentRailCopy.regionUnavailable).font(.caption).foregroundStyle(Color(red: 0.553, green: 0.145, blue: 0.090)) }
            Button("Confirm payment") { Task { await pay() } }.buttonStyle(.borderedProminent).disabled(busy || !selectedRailAvailable)
            Button("Edit details") { review=false; showMethods=false; key=UUID().uuidString }.disabled(busy)
          } else {
            Button("Review payment") { let (value,error)=parseAmount(amount); guard value != nil else {message=error ?? "Invalid amount";return}; guard reference.count<=200 else {message="Reference is too long"; return}; guard selectedRailAvailable else { message = catalog == nil ? "Loading payment methods…" : PaymentRailCopy.regionUnavailable; return }; showMethods=false; key=UUID().uuidString; review=true; message="Review before confirming. No real money moves." }.disabled(busy || !selectedRailAvailable)
          }
          Text("Recent activity").font(.title2)
          ForEach(Array(state.transactions.reversed().prefix(8)), id: \.id) { transaction in HStack { VStack(alignment:.leading){Text(transaction.name);Text(transaction.provider.rawValue).font(.caption).foregroundStyle(.secondary)};Spacer();Text(money(transaction.amount)) } }
          Text("September budgets").font(.title2)
          ForEach(state.budgets, id: \.category) { budget in HStack {Text(budget.category.rawValue);Spacer();Text(money(budget.limit))} }
        }
      }.padding(24).frame(maxWidth: 550)
    }.accessibilityHidden(showMethods)
    if showMethods {
      PaymentMethodSheet(method: $method, rails: rails) { showMethods = false }
        .transition(.move(edge: .bottom))
    }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: showMethods)
    .task {
      while !Task.isCancelled { try? await Task.sleep(for: .seconds(2)); if !busy { await refresh() } }
    }
  }
  private func connect() async {
    guard room.range(of:"^[A-Za-z0-9_-]{3,64}$",options:.regularExpression) != nil else { message="Invalid room"; return }
    generation += 1; state=nil; catalog=nil; review=false; showMethods=false; key=UUID().uuidString
    do { client=try MeridianClient(baseURL:endpoint,sessionId:room); await refresh() } catch { message=String(describing:error) }
  }
  private func refresh() async {
    guard let client else {return}; let started=generation
    do {
      let next=try await client.getState()
      if started==generation && !busy { state=next; if catalog==nil { message="Loading payment methods…" } }
      let definitions=try await client.getCatalog()
      if started==generation && !busy { catalog=definitions; message="Connected to shared Java API" }
    } catch { if started==generation {message="API unavailable: \(error)"} }
  }
  private func pay() async {
    guard let client, !busy else {return}
    guard selectedRailAvailable else { message = catalog == nil ? "Loading payment methods…" : PaymentRailCopy.regionUnavailable; return }
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
