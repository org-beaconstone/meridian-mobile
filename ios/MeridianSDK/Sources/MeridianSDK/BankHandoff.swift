import CryptoKit
import Foundation

// MARK: - Handoff Errors

public enum HandoffError: LocalizedError, Equatable {
    case disallowedURL(String)
    case invalidReturnState(String)
    case expiredReturnState
    case replayedReturnState
    case missingReturnState

    public var errorDescription: String? {
        switch self {
        case let .disallowedURL(url):
            return "URL not in allowlist: \(url)"
        case let .invalidReturnState(msg):
            return "Invalid return state: \(msg)"
        case .expiredReturnState:
            return "Return state has expired"
        case .replayedReturnState:
            return "Return state has already been used"
        case .missingReturnState:
            return "Return state parameter missing"
        }
    }
}

// MARK: - Return State Payload

/// The decoded, verified content of a return-state token.
public struct ReturnStatePayload: Codable, Sendable, Equatable {
    public let paymentId: String
    /// Unix timestamp (seconds) at which the token was issued.
    public let issuedAt: Int64
    /// Unique nonce used for replay prevention.
    public let nonce: String

    public init(paymentId: String, issuedAt: Int64, nonce: String) {
        self.paymentId = paymentId
        self.issuedAt = issuedAt
        self.nonce = nonce
    }

    /// Convenience initialiser that stamps the current time and generates a fresh nonce.
    public init(paymentId: String) {
        self.paymentId = paymentId
        self.issuedAt = Int64(Date().timeIntervalSince1970)
        self.nonce = UUID().uuidString
    }
}

// MARK: - Return State Token

/// Generates and verifies opaque, HMAC-SHA256-signed return-state tokens.
///
/// Token format: `<base64url(json_payload)>.<hex_hmac>`
public enum ReturnStateToken {

    // MARK: Generation

    /// Build a signed token string for `paymentId`.
    public static func generate(paymentId: String, signingKey: SymmetricKey) throws -> String {
        let payload = ReturnStatePayload(paymentId: paymentId)
        return try sign(payload: payload, signingKey: signingKey)
    }

    /// Build a signed token string from an existing payload (useful in tests).
    public static func sign(payload: ReturnStatePayload, signingKey: SymmetricKey) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let jsonData = try encoder.encode(payload)
        let base64Payload = base64URLEncode(jsonData)
        let mac = HMAC<SHA256>.authenticationCode(for: Data(base64Payload.utf8), using: signingKey)
        let hexMac = Data(mac).map { String(format: "%02x", $0) }.joined()
        return "\(base64Payload).\(hexMac)"
    }

    // MARK: Verification

    /// Verify the token signature and decode its payload.
    ///
    /// Throws ``HandoffError/invalidReturnState(_:)`` on any structural or cryptographic problem.
    public static func verify(token: String, signingKey: SymmetricKey) throws -> ReturnStatePayload {
        // Split on the first `.` only so nonces with dots are safe.
        guard let dotIndex = token.firstIndex(of: ".") else {
            throw HandoffError.invalidReturnState("Malformed token: missing separator")
        }
        let base64Payload = String(token[token.startIndex..<dotIndex])
        let providedHex = String(token[token.index(after: dotIndex)...])

        guard !base64Payload.isEmpty, !providedHex.isEmpty else {
            throw HandoffError.invalidReturnState("Malformed token: empty segment")
        }

        // Constant-time HMAC verification via CryptoKit.
        guard let providedMacData = Data(hexString: providedHex),
              HMAC<SHA256>.isValidAuthenticationCode(
                  providedMacData,
                  authenticating: Data(base64Payload.utf8),
                  using: signingKey
              )
        else {
            throw HandoffError.invalidReturnState("Signature mismatch")
        }

        // Decode the payload.
        guard let jsonData = base64URLDecode(base64Payload) else {
            throw HandoffError.invalidReturnState("Invalid base64url encoding")
        }

        do {
            return try JSONDecoder().decode(ReturnStatePayload.self, from: jsonData)
        } catch {
            throw HandoffError.invalidReturnState("Payload decoding failed: \(error.localizedDescription)")
        }
    }

    // MARK: Helpers

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = s.count % 4
        if remainder > 0 { s.append(String(repeating: "=", count: 4 - remainder)) }
        return Data(base64Encoded: s)
    }
}

// MARK: - Data hex helpers

private extension Data {
    /// Decode a lowercase hex string to Data.  Returns `nil` for invalid input.
    init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var data = Data(capacity: hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}

// MARK: - Return State Validator

/// Thread-safe validator that checks token signature, expiry, and replay.
public actor ReturnStateValidator {
    private var seenNonces: Set<String> = []
    private let signingKey: SymmetricKey
    /// Maximum age of a token in seconds (default 5 minutes).
    private let tokenTTL: Int64

    public init(signingKey: SymmetricKey, tokenTTL: Int64 = 300) {
        self.signingKey = signingKey
        self.tokenTTL = tokenTTL
    }

    /// Verify the token and return its payload.
    ///
    /// Throws:
    /// - ``HandoffError/invalidReturnState(_:)`` – bad signature or structure
    /// - ``HandoffError/expiredReturnState`` – token older than `tokenTTL`
    /// - ``HandoffError/replayedReturnState`` – nonce already consumed
    public func validate(token: String) throws -> ReturnStatePayload {
        let payload = try ReturnStateToken.verify(token: token, signingKey: signingKey)

        let now = Int64(Date().timeIntervalSince1970)
        guard now - payload.issuedAt <= tokenTTL else {
            throw HandoffError.expiredReturnState
        }

        guard !seenNonces.contains(payload.nonce) else {
            throw HandoffError.replayedReturnState
        }

        seenNonces.insert(payload.nonce)
        return payload
    }
}

// MARK: - Bank Handoff Manager

/// Manages external bank handoff URLs and return-URL validation.
///
/// Responsibilities:
/// - Enforce an allowlist of bank HTTPS hosts.
/// - Attach signed opaque `returnState` query parameters.
/// - Intercept and validate universal-link / app-link return URLs.
public actor BankHandoffManager {

    // MARK: Defaults

    public static let defaultAllowlist: Set<String> = [
        "secure.worldpay.com",
        "payments.worldpay.com",
        "checkout.adyen.com",
        "live.adyen.com",
    ]

    // MARK: State

    private let allowlist: Set<String>
    private let signingKey: SymmetricKey
    private let validator: ReturnStateValidator

    // MARK: Initialisation

    /// - Parameters:
    ///   - sessionId: The rehearsal session ID used to derive the HMAC signing key.
    ///   - allowlist: Set of allowed bank HTTPS hostnames.
    ///   - tokenTTL: Maximum token lifetime in seconds (default 300 s / 5 min).
    public init(
        sessionId: String,
        allowlist: Set<String> = BankHandoffManager.defaultAllowlist,
        tokenTTL: Int64 = 300
    ) {
        self.allowlist = allowlist
        // Derive a deterministic signing key from the session ID.
        let keyData = Data(SHA256.hash(data: Data(sessionId.utf8)))
        self.signingKey = SymmetricKey(data: keyData)
        self.validator = ReturnStateValidator(signingKey: signingKey, tokenTTL: tokenTTL)
    }

    // MARK: Outbound

    /// Build a bank handoff URL with a signed `returnState` query parameter.
    ///
    /// - Parameters:
    ///   - bankURL: The target bank URL (must be HTTPS and host must be allowlisted).
    ///   - paymentId: The payment identifier to embed in the return state.
    ///   - returnScheme: Custom URL scheme or HTTPS prefix the bank should redirect to.
    /// - Returns: The bank URL augmented with `returnState` and `returnScheme` query items.
    /// - Throws: ``HandoffError/disallowedURL(_:)`` if the URL fails allowlist checks.
    public func buildHandoffURL(
        bankURL: URL,
        paymentId: String,
        returnScheme: String
    ) throws -> URL {
        guard bankURL.scheme == "https" else {
            throw HandoffError.disallowedURL("Only HTTPS bank URLs are permitted")
        }
        guard let host = bankURL.host, allowlist.contains(host) else {
            throw HandoffError.disallowedURL(bankURL.absoluteString)
        }

        let token = try ReturnStateToken.generate(paymentId: paymentId, signingKey: signingKey)

        var components = URLComponents(url: bankURL, resolvingAgainstBaseURL: false)!
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "returnState", value: token))
        items.append(URLQueryItem(name: "returnScheme", value: returnScheme))
        components.queryItems = items

        guard let result = components.url else {
            throw HandoffError.disallowedURL("Could not construct handoff URL")
        }
        return result
    }

    // MARK: Inbound

    /// Handle a universal-link or custom-scheme return URL from the bank.
    ///
    /// Extracts the `returnState` parameter and validates its signature, expiry, and nonce.
    ///
    /// - Throws:
    ///   - ``HandoffError/missingReturnState`` – parameter absent or empty
    ///   - ``HandoffError/invalidReturnState(_:)`` – bad signature or structure
    ///   - ``HandoffError/expiredReturnState`` – token has expired
    ///   - ``HandoffError/replayedReturnState`` – nonce already used (replay attack)
    public func handleReturnURL(_ url: URL) async throws -> ReturnStatePayload {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let tokenItem = components.queryItems?.first(where: { $0.name == "returnState" }),
              let token = tokenItem.value, !token.isEmpty
        else {
            throw HandoffError.missingReturnState
        }

        return try await validator.validate(token: token)
    }
}
