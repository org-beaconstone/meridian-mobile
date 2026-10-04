import Foundation
import SwiftUI
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif
import MeridianSDK

@MainActor
final class ScaDialogModel: ObservableObject {
  @Published var prompt: String?
  @Published var detail: String?
  private var continuation: CheckedContinuation<Bool, Never>?

  func ask(prompt: String, detail: String) async -> Bool {
    await withCheckedContinuation { continuation in
      self.detail = detail
      self.prompt = prompt
      self.continuation = continuation
    }
  }

  func finish(_ accepted: Bool) {
    guard let continuation else { return }
    self.continuation = nil
    prompt = nil
    detail = nil
    continuation.resume(returning: accepted)
  }
}

struct DialogScaHandler: ScaChallengeHandler, @unchecked Sendable {
  private let model: ScaDialogModel

  init(model: ScaDialogModel) {
    self.model = model
  }

  func confirmEuropeanPayment(prompt: String) async -> Bool {
    let reason = prompt.isEmpty ? ScaCopy.europeanPayment : prompt
    if let system = await evaluateBiometrics(reason: reason) {
      return system
    }
    return await model.ask(
      prompt: reason,
      detail: "Face ID and Touch ID are unavailable, so this native confirmation continues the rehearsal. No provider is contacted."
    )
  }

  private func evaluateBiometrics(reason: String) async -> Bool? {
    #if canImport(LocalAuthentication)
    let context = LAContext()
    context.localizedCancelTitle = "Cancel"
    var error: NSError?
    let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    guard available else { return nil }
    do {
      return try await context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        localizedReason: reason
      )
    } catch {
      return false
    }
    #else
    _ = reason
    return nil
    #endif
  }
}
