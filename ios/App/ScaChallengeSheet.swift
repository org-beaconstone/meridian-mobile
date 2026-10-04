import LocalAuthentication
import MeridianSDK
import SwiftUI

struct ScaLaunch: Identifiable {
  let id = UUID()
  let binding: ScaPaymentBinding
}

enum DeviceBiometric {
  enum PromptResult {
    case succeeded
    case rejected
    case bypassed
    case unavailable
    case cancelled
  }

  static var isAvailable: Bool {
    let context = LAContext()
    var error: NSError?
    return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
  }

  static func authenticate() async -> PromptResult {
    let context = LAContext()
    context.localizedFallbackTitle = "Use passcode"
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
      return .unavailable
    }
    do {
      let accepted = try await context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        localizedReason: "Confirm this Meridian payment"
      )
      return accepted ? .succeeded : .rejected
    } catch let failure as LAError {
      switch failure.code {
      case .userCancel, .appCancel, .systemCancel:
        return .cancelled
      case .userFallback:
        return .bypassed
      case .biometryNotAvailable, .biometryNotEnrolled:
        return .unavailable
      default:
        return .rejected
      }
    } catch {
      return .rejected
    }
  }
}

struct ScaChallengeSheet: View {
  let binding: ScaPaymentBinding
  let onCancel: () -> Void
  let onVerified: (ScaVerification) -> Void
  @State private var session: ScaChallengeSession
  @State private var checkingBiometrics = false

  init(
    binding: ScaPaymentBinding,
    onCancel: @escaping () -> Void,
    onVerified: @escaping (ScaVerification) -> Void
  ) {
    self.binding = binding
    self.onCancel = onCancel
    self.onVerified = onVerified
    _session = State(initialValue: ScaChallengeSession(binding: binding))
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { timeline in
      let locked = session.secondsLocked(at: timeline.date)
      VStack(alignment: .leading, spacing: 16) {
        Text(session.phase == .biometric ? "Confirm it's you" : "Security passcode")
          .font(.title2)
          .accessibilityIdentifier("sca-title")
        Text("Possession plus a second factor stay inside Meridian. This check does not open a browser or a payment provider.")
          .font(.caption)
          .foregroundStyle(.secondary)
        if session.phase == .biometric {
          Button(checkingBiometrics ? "Checking biometrics…" : "Verify with biometrics") {
            Task { await runBiometrics() }
          }
          .buttonStyle(.borderedProminent)
          .disabled(checkingBiometrics)
          Button("Use passcode instead") { session.bypassBiometrics() }
            .disabled(checkingBiometrics)
        } else {
          if let banner = session.rejectionBanner {
            Text(banner)
              .font(.callout)
              .foregroundStyle(Color(red: 0.553, green: 0.145, blue: 0.090))
              .padding(12)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color(red: 1, green: 0.929, blue: 0.922))
              .clipShape(RoundedRectangle(cornerRadius: 8))
              .accessibilityIdentifier("sca-banner")
          } else if session.biometric == .unavailable {
            Text(ScaChallenge.biometricsUnavailableNote)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Text(session.maskedPasscode())
            .font(.system(size: 28, weight: .medium))
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("sca-dots")
            .accessibilityLabel("\(session.enteredCount) of 6 digits entered")
          if locked > 0 {
            Text("\(ScaChallenge.tooManyAttempts) \(locked)s remaining.")
              .font(.callout)
              .foregroundStyle(Color(red: 0.553, green: 0.145, blue: 0.090))
          } else if let message = session.passcodeMessage {
            Text(message)
              .font(.callout)
              .foregroundStyle(Color(red: 0.553, green: 0.145, blue: 0.090))
          }
          keypad(locked: locked > 0, now: timeline.date)
          Text("Fictional rehearsal passcode: \(ScaChallenge.rehearsalPin). It stays on this device and is not sent to the API.")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Button("Cancel", action: onCancel)
          .disabled(checkingBiometrics)
        Spacer(minLength: 0)
      }
      .padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .onAppear {
      if !DeviceBiometric.isAvailable {
        session.markBiometricsUnavailable()
      }
    }
  }

  private func keypad(locked: Bool, now: Date) -> some View {
    VStack(spacing: 8) {
      ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
        HStack(spacing: 8) {
          ForEach(row, id: \.self) { digit in
            digitButton(digit, locked: locked, now: now)
          }
        }
      }
      HStack(spacing: 8) {
        Color.clear.frame(maxWidth: .infinity, minHeight: 52)
        digitButton(0, locked: locked, now: now)
        Button("Delete") { session.deleteDigit(at: now) }
          .frame(maxWidth: .infinity, minHeight: 52)
          .buttonStyle(.bordered)
          .disabled(locked || session.phase != .passcode)
      }
    }
  }

  private func digitButton(_ digit: Int, locked: Bool, now: Date) -> some View {
    Button(String(digit)) {
      if let verification = session.appendDigit(digit, at: now) {
        onVerified(verification)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 52)
    .buttonStyle(.bordered)
    .disabled(locked || session.phase != .passcode)
  }

  private func runBiometrics() async {
    checkingBiometrics = true
    defer { checkingBiometrics = false }
    let outcome = await DeviceBiometric.authenticate()
    let now = Date()
    switch outcome {
    case .succeeded:
      if let verification = session.succeedBiometrics(at: now) {
        onVerified(verification)
      }
    case .rejected:
      session.rejectBiometrics()
    case .bypassed:
      session.bypassBiometrics()
    case .unavailable:
      session.markBiometricsUnavailable()
    case .cancelled:
      break
    }
  }
}
