import Foundation
import CryptoKit

// MARK: - Bank Handoff Errors

/// Errors produced during bank URL construction or return state validation
public enum BankHandoffError: LocalizedError, Sendable {
  /// The target URL's host is not on the allowlist or is not HTTPS
  case domainNotAllowed(String)
  /// The state token could not be parsed
  case malformedToken
  /// The HMAC signature on the state token does not match
  case invalidSignature
  /// The state token's issuedAt timestamp is outside the allowed window
  case tokenExpired
  /// The state token's nonce has already been consumed (replay attack)
  case tokenReplayed

  public var errorDescription: String? {
    switch self {
    case .domainNotAllowed(let host):
      return "Bank domain not in allowlist: \(host)"
    case .malformedToken:
      return "Return state token is malformed"
    case .invalidSignature:
      return "Return state token signature is invalid"
    case .tokenExpired:
      return "Return state token has expired"
    case .tokenReplayed:
      return "Return state token has already been consumed"
    }
  }
}

// MARK: - Bank Handoff

/// Utilities for external bank handoff: constructing allowlist-validated HTTPS URLs
/// with signed opaque state tokens, and validating tokens on universal link return.
///
/// Token format: `<base64url(JSON)>.<base64url(HMAC-SHA256)>`
///
/// The JSON payload (`ReturnState`) contains `paymentId`, `nonce`, and `iat` (Unix seconds).
/// The HMAC is computed over the base64url-encoded payload using the provided `SymmetricKey`.
public struct BankHandoff: Sendable {

  // MARK: - Allowlist

  /// HTTPS hostnames that the app is permitted to open for bank payment handoff.
  /// Only Worldpay is the baseline bank provider; the rehearsal endpoint is included for testing.
  public static let allowedHosts: Set<String> = [
    "payments.worldpay.com",
    "secure.worldpay.com",
    "online.worldpay.com",
    "banking.worldpay.com",
    "bank.rehearsal.meridian.internal",
  ]

  // MARK: - URL Building

  /// Construct an external bank handoff URL with a signed opaque `state` parameter
  /// and a `redirect_uri` pointing back into the app.
  ///
  /// - Parameters:
  ///   - bankURL: The bank's HTTPS base URL (host must be in `allowedHosts`)
  ///   - paymentId: Payment identifier to embed in the state token
  ///   - returnURLScheme: The app's registered universal-link or custom URL scheme
  ///   - signingKey: Symmetric key used to sign the state token with HMAC-SHA256
  /// - Throws: `BankHandoffError.domainNotAllowed` if the host/scheme is not permitted
  /// - Returns: The bank URL with `state` and `redirect_uri` query items appended
  public static func buildHandoffURL(
    bankURL: URL,
    paymentId: String,
    returnURLScheme: String,
    signingKey: SymmetricKey
  ) throws -> URL {
    guard bankURL.scheme?.lowercased() == "https",
          let host = bankURL.host,
          allowedHosts.contains(host)
    else {
      throw BankHandoffError.domainNotAllowed(
        bankURL.host.map { "\(bankURL.scheme ?? "")://\($0)" } ?? bankURL.absoluteString
      )
    }

    let stateToken = try makeStateToken(paymentId: paymentId, signingKey: signingKey)
    let returnURL = "\(returnURLScheme)://payment/return"

    guard var components = URLComponents(url: bankURL, resolvingAgainstBaseURL: false) else {
      throw BankHandoffError.malformedToken
    }
    var items = components.queryItems ?? []
    items.append(URLQueryItem(name: "state", value: stateToken))
    items.append(URLQueryItem(name: "redirect_uri", value: returnURL))
    components.queryItems = items

    guard let finalURL = components.url else {
      throw BankHandoffError.malformedToken
    }
    return finalURL
  }

  // MARK: - Return URL Validation

  /// Extract and validate the `state` token from a bank return URL.
  ///
  /// Validates in order: HMAC signature → expiry → replay (nonce uniqueness).
  /// A consumed nonce is added to `usedNonces` only after all checks pass.
  /// Replayed, expired, or tampered tokens throw without touching payment state.
  ///
  /// - Parameters:
  ///   - url: The return deep-link URL delivered via universal link or custom scheme
  ///   - signingKey: The same symmetric key used when building the handoff URL
  ///   - usedNonces: Mutable set of already-consumed nonces; updated on success
  ///   - maxAgeSeconds: Token lifetime in seconds (default 600 = 10 minutes)
  /// - Throws: `BankHandoffError` describing the failure
  /// - Returns: The decoded `ReturnState` on success
  public static func validateReturnURL(
    _ url: URL,
    signingKey: SymmetricKey,
    usedNonces: inout Set<String>,
    maxAgeSeconds: TimeInterval = 600
  ) throws -> ReturnState {
    guard
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let stateToken = components.queryItems?.first(where: { $0.name == "state" })?.value
    else {
      throw BankHandoffError.malformedToken
    }

    return try verifyStateToken(
      stateToken,
      signingKey: signingKey,
      usedNonces: &usedNonces,
      maxAgeSeconds: maxAgeSeconds
    )
  }

  // MARK: - Internal Token Helpers

  static func makeStateToken(paymentId: String, signingKey: SymmetricKey) throws -> String {
    let now = Int64(Date().timeIntervalSince1970)
    let payload = ReturnState(paymentId: paymentId, nonce: UUID().uuidString, issuedAt: now)
    let payloadData = try JSONEncoder().encode(payload)
    let payloadB64 = base64urlEncode(payloadData)

    let mac = HMAC<SHA256>.authenticationCode(
      for: Data(payloadB64.utf8),
      using: signingKey
    )
    let sigB64 = base64urlEncode(Data(mac))
    return "\(payloadB64).\(sigB64)"
  }

  static func verifyStateToken(
    _ token: String,
    signingKey: SymmetricKey,
    usedNonces: inout Set<String>,
    maxAgeSeconds: TimeInterval
  ) throws -> ReturnState {
    let parts = token.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
      .map(String.init)
    guard parts.count == 2 else { throw BankHandoffError.malformedToken }

    let payloadB64 = parts[0]
    let sigB64 = parts[1]

    guard let sigBytes = base64urlDecode(sigB64) else {
      throw BankHandoffError.malformedToken
    }
    guard
      HMAC<SHA256>.isValidAuthenticationCode(
        sigBytes,
        authenticating: Data(payloadB64.utf8),
        using: signingKey
      )
    else {
      throw BankHandoffError.invalidSignature
    }

    guard let payloadData = base64urlDecode(payloadB64) else {
      throw BankHandoffError.malformedToken
    }
    let state: ReturnState
    do {
      state = try JSONDecoder().decode(ReturnState.self, from: payloadData)
    } catch {
      throw BankHandoffError.malformedToken
    }

    // Expiry check
    let now = Date().timeIntervalSince1970
    let age = now - Double(state.issuedAt)
    guard age >= 0 && age <= maxAgeSeconds else {
      throw BankHandoffError.tokenExpired
    }

    // Replay check
    guard !usedNonces.contains(state.nonce) else {
      throw BankHandoffError.tokenReplayed
    }
    usedNonces.insert(state.nonce)

    return state
  }

  // MARK: - Base64url Codec

  static func base64urlEncode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .trimmingCharacters(in: CharacterSet(charactersIn: "="))
  }

  static func base64urlDecode(_ string: String) -> Data? {
    var s = string
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let pad = (4 - s.count % 4) % 4
    s += String(repeating: "=", count: pad)
    return Data(base64Encoded: s)
  }
}
