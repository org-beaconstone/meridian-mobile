import SwiftUI
import MeridianSDK

@main struct MeridianApp: App {
  var body: some Scene { WindowGroup { MeridianView().frame(minWidth: 350, minHeight: 650) } }
}

@MainActor struct MeridianView: View {
  @State private var model = PaymentScreenModel(
    endpoint: "http://127.0.0.1:8080/api/v1",
    room: "meridian-rehearsal"
  )
  @State private var client: MeridianClient?
  @State private var state: BankState?
  @State private var catalog: CatalogResponse?
  @State private var didRestore = false
  @SceneStorage("meridian.checkpoint") private var checkpointJSON = ""
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let direction = layoutDirectionForLanguage(Locale.current.identifier) == "rtl" ? LayoutDirection.rightToLeft : LayoutDirection.leftToRight
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("meridian").font(.largeTitle).fontWeight(.semibold)
          .accessibilityAddTraits(.isHeader)
        Text("Native SwiftUI · Fictional payment rehearsal").font(.caption)
        Group {
          TextField("API base URL", text: $model.endpoint)
          TextField("Shared rehearsal room", text: $model.room)
          Button("Connect") { Task { await connect() } }
            .frame(minHeight: 44)
            .disabled(model.busy)
        }.textFieldStyle(.roundedBorder)
        Text(model.message).font(.callout).foregroundStyle(.secondary)
        if let state {
          VStack(alignment: .leading, spacing: 8) {
            Text("Everyday account · GBP").font(.caption)
            Text(money(state.balance))
              .font(.system(size: scaledFontSize(base: 38, fontScale: fontScaleFor(bucket: fontBucket))))
              .accessibilityLabel("Everyday account balance \(money(state.balance))")
            Text("Shared room: \(model.runtime.checkpoint.sessionId)").font(.caption)
          }
          .padding(24)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(red: 0.078, green: 0.173, blue: 0.208))
          .foregroundStyle(.white)
          .clipShape(RoundedRectangle(cornerRadius: 16))
          .accessibilityElement(children: .combine)
          Text("Make a payment").font(.title2).accessibilityAddTraits(.isHeader)
          if let catalog {
            Picker("Recipient", selection: $model.recipientId) {
              ForEach(catalog.recipients, id: \.id) { Text($0.name).tag($0.id) }
            }.disabled(model.reviewing || model.busy)
          }
          TextField("Amount (GBP)", text: $model.amountInput).textFieldStyle(.roundedBorder).disabled(model.reviewing || model.busy)
          TextField("Reference", text: $model.note).textFieldStyle(.roundedBorder).disabled(model.reviewing || model.busy)
          Picker("Method", selection: $model.method) {
            Text("Debit card · Adyen").tag(PaymentMethod.card)
            Text("Bank payment · Worldpay").tag(PaymentMethod.bank)
          }.disabled(model.reviewing || model.busy)
          if model.reviewing {
            Text("Confirm \(model.amountInput) GBP to \(model.recipientId)").font(.headline)
            let a11y = confirmAccessibility()
            Button("Confirm payment") { Task { await pay() } }
              .buttonStyle(.borderedProminent)
              .frame(minHeight: CGFloat(a11y.minimumTouchTargetPt))
              .disabled(model.busy)
              .accessibilityLabel(a11y.label)
              .accessibilityHint(a11y.hint)
            Button("Edit details") { model.edit(); persist() }
              .frame(minHeight: 44)
              .disabled(model.busy)
          } else {
            Button("Review payment") {
              _ = model.review()
              persist()
            }
            .frame(minHeight: 44)
            .disabled(model.busy)
          }
          Text("Recent activity").font(.title2).accessibilityAddTraits(.isHeader)
          ForEach(Array(state.transactions.reversed().prefix(8)), id: \.id) { transaction in
            HStack {
              VStack(alignment: .leading) {
                Text(transaction.name)
                Text(transaction.provider.rawValue).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Text(money(transaction.amount))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(transaction.name), \(money(transaction.amount))")
          }
          Text("September budgets").font(.title2).accessibilityAddTraits(.isHeader)
          ForEach(state.budgets, id: \.category) { budget in
            HStack {
              Text(budget.category.rawValue)
              Spacer()
              Text(money(budget.limit))
            }
            .accessibilityElement(children: .combine)
          }
        }
      }.padding(24).frame(maxWidth: 550)
    }
    .environment(\.layoutDirection, direction)
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        if !model.busy { await refresh() }
      }
    }
    .onAppear {
      guard !didRestore else { return }
      didRestore = true
      if !checkpointJSON.isEmpty, let restored = PaymentScreenModel.restore(checkpointJSON) {
        model = restored
      }
    }
    .onOpenURL { url in
      _ = model.openReturn(url: url.absoluteString, nowMillis: nowMillis())
      persist()
    }
    .onChange(of: model.amountInput) { _ in persist() }
    .onChange(of: model.note) { _ in persist() }
  }

  private var fontBucket: String {
    switch dynamicTypeSize {
    case .xSmall, .small, .medium, .large, .xLarge:
      return "standard"
    case .xxLarge, .xxxLarge:
      return "large"
    default:
      return "accessibility"
    }
  }

  private func confirmAccessibility() -> AccessibilityDescriptor {
    let name = catalog?.recipients.first { $0.id == model.recipientId }?.name ?? model.recipientId
    return model.confirmationAccessibility(
      recipientName: name,
      language: Locale.current.identifier,
      fontScale: fontScaleFor(bucket: fontBucket),
      platform: "voiceover"
    )
  }

  private func nowMillis() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1000).rounded())
  }

  private func persist() {
    guard didRestore else { return }
    checkpointJSON = model.checkpointJSON()
  }

  private func connect() async {
    guard model.connect() else { persist(); return }
    do {
      client = try MeridianClient(baseURL: model.endpoint, sessionId: model.runtime.checkpoint.sessionId)
      state = nil
      catalog = nil
      persist()
      await refresh()
    } catch {
      model.message = String(describing: error)
      persist()
    }
  }

  private func refresh() async {
    guard let client else { return }
    let started = model.generation
    do {
      let next = try await client.getState()
      let definitions = try await client.getCatalog()
      if started == model.generation && !model.busy {
        state = next
        catalog = definitions
        model.rememberCatalog(
          CachedCatalog(
            demoDate: definitions.demoDate,
            currency: definitions.currency,
            recipientIds: definitions.recipients.map(\.id),
            providerIds: definitions.providers.map(\.id.rawValue)
          ),
          nowMillis: nowMillis()
        )
        model.message = "Connected to shared Java API"
        persist()
      }
    } catch {
      if started == model.generation {
        model.message = "API unavailable: \(error)"
        persist()
      }
    }
  }

  private func pay() async {
    guard let client, let draft = model.submitInstruction(), !model.busy else { return }
    model.busy = true
    model.generation += 1
    defer { model.busy = false; persist() }
    let method: PaymentMethod = draft.method == "bank" ? .bank : .card
    do {
      let result = try await client.submitPayment(
        recipientId: draft.recipientId,
        amountMinor: draft.amountMinor,
        method: method,
        note: draft.note,
        scenario: .success,
        idempotencyKey: draft.idempotencyKey
      )
      if result.ok {
        state = result.state
        model.markSettled()
      } else {
        model.markUncertain(reason: result.error ?? "Payment pending. Retry the same payment, not a new one.")
      }
    } catch {
      model.markUncertain(reason: "Outcome may be unknown: \(error). Retry preserves the payment key.")
    }
  }
}
