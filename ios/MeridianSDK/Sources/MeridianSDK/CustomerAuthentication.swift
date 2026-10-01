import CryptoKit
import Foundation
import Security

/// Rehearsal strong customer authentication and Worldpay bank return checks.
/// Card payments clear only after a biometric or PIN confirmation. Bank payments
/// open an allowlisted HTTPS handoff and clear only after the signed return
/// state passes integrity, expiry, and replay checks. Nothing here calls a
/// live card or bank host.

public enum ScaFactor: String, Equatable {
  case biometric
  case pin
}

public enum ReturnFailure: String, Equatable {
  case invalid
  case expired
  case replayed
  case missing
}

public enum ScaDecision: Equatable {
  case confirmed(ScaFactor)
  case rejected
  case notRequired
}

public enum ReturnStatus: Equatable {
  case accepted(String)
  case rejected(ReturnFailure)
}

public enum ReturnIntercept: Equatable {
  case token(String)
  case missingState
  case notReturnLink
}

public enum ReturnOutcome: Equatable {
  case cleared(String)
  case safeFailure(ReturnFailure, String)
  case ignored
}

public func normalizeRehearsalPin(_ pin: String) -> String? {
  let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
  guard (4...8).contains(trimmed.count), trimmed.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
  return trimmed
}

public func returnFailureMessage(_ reason: ReturnFailure) -> String {
  switch reason {
  case .invalid:
    return "The bank return could not be verified. The payment was not sent again."
  case .expired:
    return "The bank return expired. The payment was not sent again."
  case .replayed:
    return "The bank return was already used. The payment was not sent again."
  case .missing:
    return "The bank return was missing its state. The payment was not sent again."
  }
}

public enum BankAllowlist {
  public static let bankHost = "bank.worldpay.rehearsal.meridian.example"
  public static let returnHost = "app.meridian.example"
  public static let returnPath = "/bank/return"
  public static let returnURLString = "https://app.meridian.example/bank/return"
  public static let handoffPath = "/open-banking/authorize"

  public static func handoffURL(stateToken: String) -> URL? {
    guard !stateToken.isEmpty, stateToken.count <= 512 else { return nil }
    guard var components = URLComponents(string: "https://\(bankHost)\(handoffPath)") else { return nil }
    components.queryItems = [
      URLQueryItem(name: "redirect_uri", value: returnURLString),
      URLQueryItem(name: "state", value: stateToken),
    ]
    guard let url = components.url, permitsHandoff(url) else { return nil }
    return url
  }

  public static func returnURL(stateToken: String) -> URL? {
    guard !stateToken.isEmpty else { return nil }
    guard var components = URLComponents(string: "https://\(returnHost)\(returnPath)") else { return nil }
    components.queryItems = [URLQueryItem(name: "state", value: stateToken)]
    guard let url = components.url, case .token = intercept(url) else { return nil }
    return url
  }

  public static func permitsHandoff(_ url: URL) -> Bool {
    guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil else { return false }
    guard url.host == bankHost, url.path == handoffPath else { return false }
    guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return false }
    let state = items.first { $0.name == "state" }?.value
    let redirect = items.first { $0.name == "redirect_uri" }?.value
    return state?.isEmpty == false && redirect == returnURLString
  }

  public static func intercept(_ url: URL) -> ReturnIntercept {
    guard url.scheme == "https", url.user == nil, url.password == nil, url.host == returnHost else {
      return .notReturnLink
    }
    var path = url.path
    if path.count > 1, path.hasSuffix("/") { path.removeLast() }
    guard path == returnPath else { return .notReturnLink }
    guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
          let state = items.first(where: { $0.name == "state" })?.value,
          !state.isEmpty
    else { return .missingState }
    return .token(state)
  }

  public static func openIfAllowlisted(_ url: URL, open: (URL) -> Bool) -> Bool {
    guard permitsHandoff(url) else { return false }
    return open(url)
  }
}

public final class ReturnStateSigner {
  private let secret: SymmetricKey
  private let ttl: TimeInterval
  private let clock: () -> Date
  private let random: (Int) -> Data
  private var consumed: Set<String> = []

  public init(
    secret: Data,
    ttl: TimeInterval = 300,
    clock: @escaping () -> Date = Date.init,
    random: @escaping (Int) -> Data = ReturnStateSigner.secureRandom
  ) {
    precondition(secret.count >= 16, "Return state signing secret is too short")
    precondition(ttl >= 30 && ttl <= 900, "Return state lifetime is out of range")
    self.secret = SymmetricKey(data: secret)
    self.ttl = ttl
    self.clock = clock
    self.random = random
  }

  public static func randomSecret() -> Data { secureRandom(32) }

  public static func secureRandom(_ count: Int) -> Data {
    var data = Data(count: count)
    let status = data.withUnsafeMutableBytes { buffer in
      SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
    }
    precondition(status == errSecSuccess, "Secure random failed")
    return data
  }

  public func issue(binding: String) -> String {
    precondition(!binding.isEmpty, "Return state binding is required")
    let nonce = base64Url(random(16))
    let exp = String(Int(clock().timeIntervalSince1970) + Int(ttl))
    let mac = base64Url(sign(nonce: nonce, exp: exp, binding: binding))
    return "v1.\(nonce).\(exp).\(mac)"
  }

  public func validate(token: String, binding: String) -> ReturnStatus {
    guard !binding.isEmpty, token.count <= 512, token.count >= 16 else {
      return .rejected(.invalid)
    }
    let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 4, parts[0] == "v1" else { return .rejected(.invalid) }
    let nonce = parts[1]
    let expText = parts[2]
    let signatureText = parts[3]
    guard !nonce.isEmpty, expText.allSatisfy(\.isNumber), let exp = Int(expText), let signature = base64UrlDecode(signatureText) else {
      return .rejected(.invalid)
    }
    let expected = sign(nonce: nonce, exp: expText, binding: binding)
    guard constantTimeEquals(signature, expected) else { return .rejected(.invalid) }
    guard consumed.insert(nonce).inserted else { return .rejected(.replayed) }
    if Int(clock().timeIntervalSince1970) >= exp {
      consumed.remove(nonce)
      return .rejected(.expired)
    }
    return .accepted(nonce)
  }

  private func sign(nonce: String, exp: String, binding: String) -> Data {
    let message = Data("v1\n\(nonce)\n\(exp)\n\(binding)".utf8)
    return Data(HMAC<SHA256>.authenticationCode(for: message, using: secret))
  }
}

/// Gates a single payment draft. The idempotency key is fixed for the draft.
/// Failed SCA and rejected bank returns leave the key in place and do not submit.
public final class PaymentAttempt {
  public let idempotencyKey: String
  public let method: PaymentMethod
  private let signer: ReturnStateSigner
  private let enrolledPin: String
  private var outstandingToken: String?
  private var cleared = false
  private var completed = false
  private var submitInFlight = false
  public private(set) var submissionCount = 0

  public init(idempotencyKey: String, method: PaymentMethod, signer: ReturnStateSigner, enrolledPin: String) {
    self.idempotencyKey = idempotencyKey
    self.method = method
    self.signer = signer
    self.enrolledPin = normalizeRehearsalPin(enrolledPin) ?? ""
  }

  public var canRetry: Bool { cleared && !completed && !submitInFlight }
  public var isSubmitting: Bool { submitInFlight }

  public func applySca(biometricAccepted: Bool, enteredPin: String) -> ScaDecision {
    guard method == .card, !completed else { return .notRequired }
    let decision: ScaDecision
    if biometricAccepted {
      decision = .confirmed(.biometric)
    } else if !enrolledPin.isEmpty, normalizeRehearsalPin(enteredPin) == enrolledPin {
      decision = .confirmed(.pin)
    } else {
      decision = .rejected
    }
    if !submitInFlight {
      if case .confirmed = decision { cleared = true } else { cleared = false }
    }
    return decision
  }

  @discardableResult
  public func resumeAfterSca(biometricAccepted: Bool, enteredPin: String, submit: (String) -> Void) -> ScaDecision {
    let decision = applySca(biometricAccepted: biometricAccepted, enteredPin: enteredPin)
    if case .confirmed = decision {
      submitIfCleared(submit)
    }
    return decision
  }

  public func startHandoff(open: (URL) -> Bool) -> URL? {
    guard method == .bank, !completed, !submitInFlight else { return nil }
    let token = signer.issue(binding: idempotencyKey)
    guard let url = BankAllowlist.handoffURL(stateToken: token) else { return nil }
    guard BankAllowlist.openIfAllowlisted(url, open: open) else { return nil }
    outstandingToken = token
    if !submitInFlight { cleared = false }
    return url
  }

  public func rehearsalReturnURL() -> URL? {
    guard let outstandingToken else { return nil }
    return BankAllowlist.returnURL(stateToken: outstandingToken)
  }

  public func handleReturn(_ url: URL) -> ReturnOutcome {
    switch BankAllowlist.intercept(url) {
    case .notReturnLink:
      return .ignored
    case .missingState:
      return .safeFailure(.missing, idempotencyKey)
    case let .token(token):
      return accept(token)
    }
  }

  @discardableResult
  public func resumeAfterReturn(_ url: URL, submit: (String) -> Void) -> ReturnOutcome {
    let outcome = handleReturn(url)
    if case .cleared = outcome {
      submitIfCleared(submit)
    }
    return outcome
  }

  @discardableResult
  public func submitIfCleared(_ submit: (String) -> Void) -> Bool {
    guard cleared, !completed, !submitInFlight else { return false }
    submitInFlight = true
    submissionCount += 1
    submit(idempotencyKey)
    return true
  }

  public func markCompleted() {
    completed = true
    cleared = false
    submitInFlight = false
    outstandingToken = nil
  }

  public func releaseForRetry() {
    if !completed && cleared { submitInFlight = false }
  }

  private func accept(_ token: String) -> ReturnOutcome {
    let matchesOutstanding = token == outstandingToken
    switch signer.validate(token: token, binding: idempotencyKey) {
    case .accepted:
      guard matchesOutstanding, !completed else {
        return .safeFailure(.invalid, idempotencyKey)
      }
      outstandingToken = nil
      if !submitInFlight { cleared = true }
      return .cleared(idempotencyKey)
    case let .rejected(reason):
      return .safeFailure(reason, idempotencyKey)
    }
  }
}

private func base64Url(_ data: Data) -> String {
  data.base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
}

private func base64UrlDecode(_ text: String) -> Data? {
  guard !text.contains(where: { $0 == "=" || $0 == "+" || $0 == "/" || $0.isWhitespace }) else { return nil }
  var padded = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
  let remainder = padded.count % 4
  if remainder == 1 { return nil }
  if remainder > 0 { padded += String(repeating: "=", count: 4 - remainder) }
  return Data(base64Encoded: padded)
}

private func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
  guard lhs.count == rhs.count else { return false }
  var mismatch: UInt8 = 0
  for index in 0..<lhs.count {
    mismatch |= lhs[index] ^ rhs[index]
  }
  return mismatch == 0
}
