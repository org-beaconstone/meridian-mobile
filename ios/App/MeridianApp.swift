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
  @State private var currency: CurrencyCode = .gbp
  @State private var railId = PaymentRail.gbpBaseline[0].id
  @State private var cachedGbp = PaymentRail.gbpBaseline
  @State private var surface = resolvePaymentSurface(flagEnabled: false, providers: nil, cachedGbp: PaymentRail.gbpBaseline).surface
  @State private var key = UUID().uuidString
  @State private var review = false
  @State private var busy = false
  @State private var message = "Connect to the Spring Boot API to start."
  @State private var generation = 0

  private var selectedCurrency: CurrencyCode {
    surface.currencies.contains(currency) ? currency : .gbp
  }

  private var visibleRails: [PaymentRail] {
    let matching = surface.rails.filter { $0.currency == selectedCurrency }
    return matching.isEmpty ? surface.rails : matching
  }

  private var currencyBinding: Binding<CurrencyCode> {
    Binding(
      get: { selectedCurrency },
      set: { newValue in
        let next = reconcileSelection(surface: surface, currency: newValue, railId: railId, reviewing: review)
        currency = next.currency
        railId = next.railId
        if review && !next.reviewing {
          review = false
          key = UUID().uuidString
        }
      }
    )
  }

  private var railBinding: Binding<String> {
    Binding(
      get: {
        if visibleRails.contains(where: { $0.id == railId }) { return railId }
        return visibleRails.first?.id ?? railId
      },
      set: { newValue in
        railId = newValue
      }
    )
  }

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
            Text(surface.flagEnabled ? "EU payments on for this cohort" : "GBP · Adyen card and Worldpay bank").font(.caption2)
          }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Color(red:0.078,green:0.173,blue:0.208)).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 16))
          Text("Make a payment").font(.title2)
          if let catalog {
            Picker("Recipient", selection: $recipient) { ForEach(catalog.recipients, id: \.id) { Text($0.name).tag($0.id) } }.disabled(review || busy)
          }
          if surface.currencies.contains(.eur) {
            Picker("Currency", selection: currencyBinding) {
              Text("GBP").tag(CurrencyCode.gbp)
              Text("EUR").tag(CurrencyCode.eur)
            }.disabled(review || busy)
          }
          TextField("Amount (\(selectedCurrency.rawValue))", text: $amount).textFieldStyle(.roundedBorder).disabled(review || busy)
          TextField("Reference", text: $reference).textFieldStyle(.roundedBorder).disabled(review || busy)
          Picker("Method", selection: railBinding) {
            ForEach(visibleRails) { rail in Text(rail.label).tag(rail.id) }
          }.disabled(review || busy)
          if review {
            Text("Confirm \(amount) \(selectedCurrency.rawValue) to \(recipient)").font(.headline)
            Button("Confirm payment") { Task { await pay() } }.buttonStyle(.borderedProminent).disabled(busy)
            Button("Edit details") { review=false; key=UUID().uuidString }.disabled(busy)
          } else {
            Button("Review payment") { let (value,error)=parseAmount(amount, currency: selectedCurrency); guard value != nil else {message=error ?? "Invalid amount";return}; guard reference.count<=200 else {message="Reference is too long"; return}; key=UUID().uuidString; review=true; message="Review before confirming. No real money moves." }.disabled(busy)
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
    generation += 1
    state=nil
    catalog=nil
    review=false
    key=UUID().uuidString
    currency = .gbp
    railId = PaymentRail.gbpBaseline[0].id
    cachedGbp = PaymentRail.gbpBaseline
    surface = resolvePaymentSurface(flagEnabled: false, providers: nil, cachedGbp: PaymentRail.gbpBaseline).surface
    do { client=try MeridianClient(baseURL:endpoint,sessionId:room); await refresh() } catch { message=String(describing:error) }
  }

  @discardableResult
  private func applySurface(flagEnabled: Bool, providers: [Provider]?) -> Bool {
    let previous = surface.flagEnabled
    let resolved = resolvePaymentSurface(flagEnabled: flagEnabled, providers: providers, cachedGbp: cachedGbp)
    cachedGbp = resolved.cachedGbp
    surface = resolved.surface
    let next = reconcileSelection(surface: resolved.surface, currency: currency, railId: railId, reviewing: review)
    let paused = review && !next.reviewing && previous && !flagEnabled
    if review && !next.reviewing { key = UUID().uuidString }
    currency = next.currency
    railId = next.railId
    review = next.reviewing
    if paused {
      message = "European payments are paused. GBP card and bank payments are still available."
    }
    return paused
  }

  private func refresh() async {
    guard let client else {return}
    let started=generation
    let eu = await client.mobileEuPaymentsEnabled()
    do {
      let next=try await client.getState()
      let definitions=try await client.getCatalog()
      if started==generation && !busy {
        state=next
        catalog=definitions
        let paused = applySurface(flagEnabled: eu, providers: definitions.providers)
        if !paused {
          message = eu ? "Connected to shared Java API · EU payments on" : "Connected to shared Java API"
        }
      }
    } catch {
      if started==generation && !busy {
        applySurface(flagEnabled: eu, providers: catalog?.providers)
        message="API unavailable: \(error)"
      }
    }
  }

  private func pay() async {
    guard let client, !busy else {return}
    let selectedId = visibleRails.contains(where: { $0.id == railId }) ? railId : visibleRails.first?.id
    guard let rail = surface.rails.first(where: { $0.id == selectedId }) else {
      message = "Payment method unavailable. GBP card and bank payments are still available."
      review = false
      return
    }
    // EUR is gated by the flag. The shared ledger still accepts integer GBP pence only,
    // and a timeout must not move this attempt onto another provider.
    if rail.currency != .gbp {
      message = "EUR stays on this device. The shared ledger settles in GBP pence, so no payment was sent."
      return
    }
    let methodForPayment = rail.method
    let keyForPayment = key
    busy=true
    generation += 1
    defer {busy=false}
    do {
      let (minor,error)=parseAmount(amount, currency: .gbp)
      guard let minor else {message=error ?? "Invalid amount";return}
      let result=try await client.submitPayment(recipientId:recipient,amountMinor:minor,method:methodForPayment,note:reference,scenario:.success,idempotencyKey:keyForPayment)
      if result.ok {state=result.state;review=false;amount="";reference="";key=UUID().uuidString;message="Demo payment completed. Other clients will refresh."}
      else {message=result.error ?? "Payment pending. Retry the same payment, not a new one."}
    } catch {message="Outcome may be unknown: \(error). Retry preserves the payment key."}
  }
}
