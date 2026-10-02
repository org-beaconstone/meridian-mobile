import SwiftUI
import MeridianSDK

@main struct MeridianApp: App {
  var body: some Scene { WindowGroup { MeridianView().frame(minWidth: 350, minHeight: 650) } }
}

// MARK: - Main View

@MainActor struct MeridianView: View {
  @State private var endpoint = "http://127.0.0.1:8080/api/v1"
  @State private var room = "meridian-rehearsal"
  @State private var client: MeridianClient?
  @State private var state: BankState?
  @State private var catalog: CatalogResponse?
  @State private var recipient = "northline-studio"
  @State private var amount = ""
  @State private var reference = ""
  @State private var selectedMethod: PaymentMethodDescriptor?
  @State private var selectedBank: BankOption?
  @State private var showMethodSheet = false
  @State private var showBankSheet = false
  @State private var key = UUID().uuidString
  @State private var review = false
  @State private var busy = false
  @State private var message = "Connect to the Spring Boot API to start."
  @State private var generation = 0

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// Full-screen on iPad or when the user has enabled large accessibility text sizes.
  private var sheetDetents: Set<PresentationDetent> {
    (horizontalSizeClass == .regular || dynamicTypeSize >= .accessibility1)
      ? [.large]
      : [.medium, .large]
  }

  private var descriptors: [PaymentMethodDescriptor] {
    paymentMethodDescriptors(from: catalog?.providers ?? [])
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
          }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.078, green: 0.173, blue: 0.208))
            .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 16))

          Text("Make a payment").font(.title2)
          if let catalog {
            Picker("Recipient", selection: $recipient) {
              ForEach(catalog.recipients, id: \.id) { Text($0.name).tag($0.id) }
            }.disabled(review || busy)
          }
          TextField("Amount (GBP)", text: $amount).textFieldStyle(.roundedBorder).disabled(review || busy)
          TextField("Reference", text: $reference).textFieldStyle(.roundedBorder).disabled(review || busy)

          // Dynamic payment-method selector — replaces fixed Adyen/Worldpay picker
          MethodSelectorButton(
            selected: selectedMethod,
            catalogLoaded: catalog != nil,
            hasDescriptors: !descriptors.isEmpty,
            disabled: review || busy
          ) { showMethodSheet = true }

          // Bank selector — only visible when the chosen method requires a bank choice
          if selectedMethod?.requiresBankChoice == true {
            BankSelectorButton(selected: selectedBank, disabled: review || busy) {
              showBankSheet = true
            }
          }

          if review {
            reviewSection
          } else {
            Button("Review payment") {
              let (value, error) = parseAmount(amount)
              guard value != nil else { message = error ?? "Invalid amount"; return }
              guard reference.count <= 200 else { message = "Reference is too long"; return }
              guard selectedMethod != nil else { message = "Please select a payment method"; return }
              if selectedMethod?.requiresBankChoice == true && selectedBank == nil {
                message = "Please select a bank"; return
              }
              key = UUID().uuidString; review = true
              message = "Review before confirming. No real money moves."
            }.disabled(busy)
          }

          Text("Recent activity").font(.title2)
          ForEach(Array(state.transactions.reversed().prefix(8)), id: \.id) { txn in
            HStack {
              VStack(alignment: .leading) {
                Text(txn.name)
                Text(txn.provider).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Text(money(txn.amount))
            }
          }
          Text("September budgets").font(.title2)
          ForEach(state.budgets, id: \.category) { budget in
            HStack { Text(budget.category.rawValue); Spacer(); Text(money(budget.limit)) }
          }
        }
      }.padding(24).frame(maxWidth: 550)
    }
    .sheet(isPresented: $showMethodSheet) {
      PaymentMethodSheetView(methods: descriptors, selected: $selectedMethod)
        .presentationDetents(sheetDetents)
        .onDisappear {
          if selectedMethod?.requiresBankChoice == false { selectedBank = nil }
        }
    }
    .sheet(isPresented: $showBankSheet) {
      BankSelectorView(selected: $selectedBank)
        .presentationDetents(sheetDetents)
    }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        if !busy { await refresh() }
      }
    }
  }

  // MARK: - Review section

  private var reviewSection: some View {
    Group {
      Text("Confirm \(amount) GBP to \(recipient)").font(.headline)
      if let m = selectedMethod {
        Text("via \(m.label) · \(m.providerName)").font(.caption).foregroundStyle(.secondary)
      }
      if let b = selectedBank {
        Text("Bank: \(b.name)").font(.caption).foregroundStyle(.secondary)
      }
      Button("Confirm payment") { Task { await pay() } }.buttonStyle(.borderedProminent).disabled(busy)
      Button("Edit details") { review = false; key = UUID().uuidString }.disabled(busy)
    }
  }

  // MARK: - Actions

  private func connect() async {
    guard room.range(of: "^[A-Za-z0-9_-]{3,64}$", options: .regularExpression) != nil else {
      message = "Invalid room"; return
    }
    generation += 1; state = nil; catalog = nil; review = false; key = UUID().uuidString
    selectedMethod = nil; selectedBank = nil
    do {
      client = try MeridianClient(baseURL: endpoint, sessionId: room)
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
        state = next; catalog = definitions; message = "Connected to shared Java API"
        // Auto-select the first eligible method from the updated catalog
        if selectedMethod == nil {
          selectedMethod = paymentMethodDescriptors(from: definitions.providers)
            .first(where: { $0.eligible })
        }
      }
    } catch {
      if started == generation { message = "API unavailable: \(error)" }
    }
  }

  private func pay() async {
    guard let client, let descriptor = selectedMethod, !busy else { return }
    busy = true; generation += 1
    defer { busy = false }
    do {
      let (minor, error) = parseAmount(amount)
      guard let minor else { message = error ?? "Invalid amount"; return }
      let result = try await client.submitPayment(
        recipientId: recipient,
        amountMinor: minor,
        method: descriptor.method,
        note: reference,
        scenario: .success,
        idempotencyKey: key
      )
      if result.ok {
        state = result.state; review = false; amount = ""; reference = ""
        key = UUID().uuidString
        message = "Demo payment completed. Other clients will refresh."
      } else {
        message = result.error ?? "Payment pending. Retry the same payment, not a new one."
      }
    } catch { message = "Outcome may be unknown: \(error). Retry preserves the payment key." }
  }
}

// MARK: - Method Selector Button

private struct MethodSelectorButton: View {
  let selected: PaymentMethodDescriptor?
  let catalogLoaded: Bool
  let hasDescriptors: Bool
  let disabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        if let m = selected {
          Image(systemName: m.logoSymbol).font(.title3).foregroundStyle(.blue).frame(width: 28)
          VStack(alignment: .leading, spacing: 2) {
            Text(m.label).font(.body).foregroundStyle(.primary)
            Text(m.providerName).font(.caption).foregroundStyle(.secondary)
          }
        } else if !catalogLoaded {
          SkeletonRow(width: 120)
        } else {
          Image(systemName: "creditcard").foregroundStyle(.secondary).frame(width: 28)
          Text("Select payment method").foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
      }
      .padding(12)
      .background(Color(.secondarySystemBackground))
      .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    .disabled(disabled || (!hasDescriptors && catalogLoaded))
  }
}

// MARK: - Bank Selector Button

private struct BankSelectorButton: View {
  let selected: BankOption?
  let disabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: "building.columns").font(.title3).foregroundStyle(.blue).frame(width: 28)
        if let b = selected {
          VStack(alignment: .leading, spacing: 2) {
            Text(b.name).font(.body).foregroundStyle(.primary)
            Text(b.sortCode).font(.caption).foregroundStyle(.secondary)
          }
        } else {
          Text("Select bank").foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
      }
      .padding(12)
      .background(Color(.secondarySystemBackground))
      .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    .disabled(disabled)
  }
}

// MARK: - Payment Method Sheet

struct PaymentMethodSheetView: View {
  let methods: [PaymentMethodDescriptor]
  @Binding var selected: PaymentMethodDescriptor?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Group {
        if methods.isEmpty {
          emptyState
        } else {
          List(methods) { descriptor in
            methodRow(descriptor)
          }
          .listStyle(.plain)
        }
      }
      .navigationTitle("Payment method")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }

  private func methodRow(_ descriptor: PaymentMethodDescriptor) -> some View {
    Button {
      selected = descriptor
      dismiss()
    } label: {
      HStack(spacing: 14) {
        Image(systemName: descriptor.logoSymbol)
          .font(.title2)
          .foregroundStyle(descriptor.eligible ? Color.blue : Color.secondary)
          .frame(width: 36)
        VStack(alignment: .leading, spacing: 2) {
          Text(descriptor.label).font(.body)
          Text(descriptor.providerName).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        if !descriptor.eligible {
          Text("Unavailable")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color(.tertiarySystemBackground))
            .clipShape(Capsule())
        }
        if selected?.id == descriptor.id {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
        }
      }
      .contentShape(Rectangle())
      .opacity(descriptor.eligible ? 1 : 0.45)
    }
    .disabled(!descriptor.eligible)
    .listRowSeparator(.hidden)
    .padding(.vertical, 6)
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Spacer()
      Image(systemName: "creditcard.trianglebadge.exclamationmark")
        .font(.system(size: 52))
        .foregroundStyle(.secondary)
      Text("No payment methods available")
        .font(.headline)
      Text("Please try again later.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Spacer()
    }
    .padding()
  }
}

// MARK: - Bank Selector Sheet

struct BankSelectorView: View {
  @Binding var selected: BankOption?
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  private var filtered: [BankOption] {
    query.isEmpty
      ? demoBanks
      : demoBanks.filter { $0.name.localizedCaseInsensitiveContains(query) }
  }

  var body: some View {
    NavigationStack {
      Group {
        if filtered.isEmpty {
          ContentUnavailableView.search(text: query)
        } else {
          List(filtered) { bank in
            Button {
              selected = bank
              dismiss()
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(bank.name).font(.body)
                  Text(bank.sortCode).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selected?.id == bank.id {
                  Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                }
              }
              .contentShape(Rectangle())
            }
            .listRowSeparator(.hidden)
          }
          .listStyle(.plain)
        }
      }
      .searchable(text: $query, prompt: "Search banks")
      .navigationTitle("Select bank")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }
}

// MARK: - Skeleton Loading Row

struct SkeletonRow: View {
  let width: CGFloat
  @State private var animating = false

  var body: some View {
    RoundedRectangle(cornerRadius: 4)
      .fill(Color(.tertiarySystemBackground))
      .frame(width: width, height: 14)
      .opacity(animating ? 0.35 : 0.75)
      .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: animating)
      .onAppear { animating = true }
  }
}
