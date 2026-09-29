import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MeridianSDK

@main
struct MeridianSDKChecks {
  static func main() async {
    print("=== Meridian SDK Checks ===\n")

    var passed = 0
    var failed = 0

    // CHECK 1: parseAmount valid integer
    print("1. parseAmount valid integer...")
    let (pence1, err1) = parseAmount("10")
    if pence1 == 1000 && err1 == nil {
      print("  ✓ parseAmount(\"10\") = 1000 pence")
      passed += 1
    } else {
      print("  ✗ Expected 1000 pence, got: \(pence1 ?? 0)")
      failed += 1
    }

    // CHECK 2: parseAmount valid decimal
    print("2. parseAmount valid decimal...")
    let (pence2, err2) = parseAmount("10.50")
    if pence2 == 1050 && err2 == nil {
      print("  ✓ parseAmount(\"10.50\") = 1050 pence")
      passed += 1
    } else {
      print("  ✗ Expected 1050 pence, got: \(pence2 ?? 0)")
      failed += 1
    }

    // CHECK 3: parseAmount single decimal
    print("3. parseAmount single decimal...")
    let (pence3, err3) = parseAmount("10.5")
    if pence3 == 1050 && err3 == nil {
      print("  ✓ parseAmount(\"10.5\") = 1050 pence")
      passed += 1
    } else {
      print("  ✗ Expected 1050 pence, got: \(pence3 ?? 0)")
      failed += 1
    }

    // CHECK 4: parseAmount zero rejected
    print("4. parseAmount zero rejected...")
    let (pence4, err4) = parseAmount("0")
    if pence4 == nil && err4 != nil {
      print("  ✓ parseAmount(\"0\") correctly rejected")
      passed += 1
    } else {
      print("  ✗ Should reject zero")
      failed += 1
    }

    // CHECK 5: parseAmount negative rejected
    print("5. parseAmount negative rejected...")
    let (pence5, err5) = parseAmount("-10.50")
    if pence5 == nil && err5 != nil {
      print("  ✓ parseAmount(\"-10.50\") correctly rejected")
      passed += 1
    } else {
      print("  ✗ Should reject negative amounts")
      failed += 1
    }

    // CHECK 6: parseAmount exponent rejected
    print("6. parseAmount exponent rejected...")
    let (pence6, err6) = parseAmount("1e3")
    if pence6 == nil && err6 != nil {
      print("  ✓ parseAmount(\"1e3\") correctly rejected")
      passed += 1
    } else {
      print("  ✗ Should reject exponent notation")
      failed += 1
    }

    // CHECK 7: parseAmount too many decimals rejected
    print("7. parseAmount too many decimals...")
    let (pence7, err7) = parseAmount("10.501")
    if pence7 == nil && err7 != nil {
      print("  ✓ parseAmount(\"10.501\") correctly rejected")
      passed += 1
    } else {
      print("  ✗ Should reject more than 2 decimals")
      failed += 1
    }

    // CHECK 8: parseAmount too large rejected
    print("8. parseAmount too large...")
    let (pence8, err8) = parseAmount("10001")
    if pence8 == nil && err8 != nil {
      print("  ✓ parseAmount(\"10001\") correctly rejected")
      passed += 1
    } else {
      print("  ✗ Should reject amounts > 10000")
      failed += 1
    }

    // CHECK 9: parseAmount empty rejected
    print("9. parseAmount empty string...")
    let (pence9, err9) = parseAmount("")
    if pence9 == nil && err9 != nil {
      print("  ✓ parseAmount(\"\") correctly rejected")
      passed += 1
    } else {
      print("  ✗ Should reject empty string")
      failed += 1
    }

    // CHECK 10: parseAmount max valid
    print("10. parseAmount max valid...")
    let (pence10, err10) = parseAmount("10000")
    if pence10 == 1_000_000 && err10 == nil {
      print("  ✓ parseAmount(\"10000\") = 1000000 pence")
      passed += 1
    } else {
      print("  ✗ Expected 1000000 pence, got: \(pence10 ?? 0)")
      failed += 1
    }

    // CHECK 11: money formatting pounds
    print("11. money formatting pounds...")
    let formatted11 = money(1050)
    if formatted11 == "£10.50" {
      print("  ✓ money(1050) = £10.50")
      passed += 1
    } else {
      print("  ✗ Expected £10.50, got: \(formatted11)")
      failed += 1
    }

    // CHECK 12: money formatting pence
    print("12. money formatting pence...")
    let formatted12 = money(100)
    if formatted12 == "£1.00" {
      print("  ✓ money(100) = £1.00")
      passed += 1
    } else {
      print("  ✗ Expected £1.00, got: \(formatted12)")
      failed += 1
    }

    // CHECK 13: BankState JSON decoding
    print("13. BankState JSON decoding...")
    let bankStateJson = """
    {
      "version": 1,
      "balance": 1248050,
      "transactions": [],
      "budgets": []
    }
    """
    do {
      let decoder = JSONDecoder()
      let state = try decoder.decode(
        BankState.self,
        from: bankStateJson.data(using: .utf8)!
      )
      if state.version == 1 && state.balance == 1_248_050 {
        print("  ✓ BankState decoded: v=\(state.version), balance=\(state.balance)")
        passed += 1
      } else {
        print("  ✗ Fields mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ Decoding failed: \(error)")
      failed += 1
    }

    // CHECK 14: PaymentResponse success decoding
    print("14. PaymentResponse success decoding...")
    let paymentJson = """
    {
      "ok": true,
      "error": null,
      "code": null,
      "state": {
        "version": 1,
        "balance": 1000000,
        "transactions": [],
        "budgets": []
      },
      "transaction": null
    }
    """
    do {
      let decoder = JSONDecoder()
      let response = try decoder.decode(
        PaymentResponse.self,
        from: paymentJson.data(using: .utf8)!
      )
      if response.ok && response.error == nil {
        print("  ✓ PaymentResponse success: ok=\(response.ok)")
        passed += 1
      } else {
        print("  ✗ Response fields mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ Decoding failed: \(error)")
      failed += 1
    }

    // CHECK 15: HTTP 202 pending response
    print("15. HTTP 202 pending response...")
    let pendingJson = """
    {
      "ok": false,
      "error": "Payment pending confirmation",
      "code": "PAYMENT_PENDING",
      "state": null,
      "transaction": null
    }
    """
    do {
      let decoder = JSONDecoder()
      let response = try decoder.decode(
        PaymentResponse.self,
        from: pendingJson.data(using: .utf8)!
      )
      if !response.ok && response.code == "PAYMENT_PENDING" {
        print("  ✓ HTTP 202 response decoded: code=\(response.code ?? "nil")")
        passed += 1
      } else {
        print("  ✗ Response fields mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ Decoding failed: \(error)")
      failed += 1
    }

    // CHECK 16: Recipient JSON decoding
    print("16. Recipient JSON decoding...")
    let recipientJson = """
    {
      "id": "alice-001",
      "name": "Alice",
      "initials": "A",
      "detail": "GH Bank",
      "category": "Shopping",
      "color": "#007AFF"
    }
    """
    do {
      let decoder = JSONDecoder()
      let recipient = try decoder.decode(
        Recipient.self,
        from: recipientJson.data(using: .utf8)!
      )
      if recipient.id == "alice-001" && recipient.name == "Alice" {
        print("  ✓ Recipient decoded: id=\(recipient.id), name=\(recipient.name)")
        passed += 1
      } else {
        print("  ✗ Recipient fields mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ Decoding failed: \(error)")
      failed += 1
    }

    // CHECK 17: CatalogResponse JSON decoding
    print("17. CatalogResponse JSON decoding...")
    let catalogJson = """
    {
      "demoDate": "2026-09-18",
      "recipients": [
        {"id": "alice-001", "name": "Alice", "initials": "A", "detail": "GH Bank", "category": "Shopping", "color": "#007AFF"}
      ],
      "providers": [
        {"id": "adyen", "name": "Adyen", "description": "Card processor", "methods": ["card"]}
      ]
    }
    """
    do {
      let decoder = JSONDecoder()
      let catalog = try decoder.decode(
        CatalogResponse.self,
        from: catalogJson.data(using: .utf8)!
      )
      if catalog.demoDate == "2026-09-18" && catalog.recipients.count == 1 {
        print("  ✓ CatalogResponse decoded: recipients=\(catalog.recipients.count), providers=\(catalog.providers.count)")
        passed += 1
      } else {
        print("  ✗ Catalog fields mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ Decoding failed: \(error)")
      failed += 1
    }

    // CHECK 18: MeridianClient initialization
    print("18. MeridianClient initialization...")
    do {
      _ = try MeridianClient(
        baseURL: "http://localhost:8080/api/v1",
        sessionId: "test-session"
      )
      print("  ✓ Client initialized successfully")
      passed += 1
    } catch {
      print("  ✗ Initialization failed: \(error)")
      failed += 1
    }

    // CHECK 19: Client rejects empty session
    print("19. Client rejects empty session...")
    do {
      _ = try MeridianClient(
        baseURL: "http://localhost:8080/api/v1",
        sessionId: ""
      )
      print("  ✗ Should have rejected empty session ID")
      failed += 1
    } catch MeridianError.missingSession {
      print("  ✓ Client correctly rejected empty session ID")
      passed += 1
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 20: Client rejects invalid URL
    print("20. Client rejects invalid URL...")
    do {
      _ = try MeridianClient(
        baseURL: "not a url",
        sessionId: "test-session"
      )
      print("  ✗ Should have rejected invalid URL")
      failed += 1
    } catch MeridianError.invalidURL {
      print("  ✓ Client correctly rejected invalid URL")
      passed += 1
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    await runTelemetryChecks(passed: &passed, failed: &failed)

    // Summary
    let total = passed + failed
    print("\n=== Results ===")
    print("Passed: \(passed)/\(total)")
    print("Failed: \(failed)/\(total)")

    if failed > 0 {
      exit(1)
    }
  }

  static func check(_ name: String, _ condition: Bool, passed: inout Int, failed: inout Int) {
    if condition {
      print("  ✓ \(name)")
      passed += 1
    } else {
      print("  ✗ \(name)")
      failed += 1
    }
  }

  static func runTelemetryChecks(passed: inout Int, failed: inout Int) async {
    print("21. sanitizer redacts PAN and IBAN...")
    let pan = "4111111111111111"
    let iban = "GB82WEST12345698765432"
    let cleaned = Sanitizer.sanitize("pay \(pan) and 4111-1111-1111-1111 to \(iban) / GB82 WEST 1234 5698 7654 32")
    check(
      "sanitizer redacts PAN and IBAN",
      !cleaned.contains(pan) && !cleaned.contains("4111-1111") && !cleaned.contains(iban) && !cleaned.contains("WEST 1234")
        && cleaned.contains("[REDACTED_PAN]") && cleaned.contains("[REDACTED_IBAN]")
        && Sanitizer.sanitize("Insufficient balance") == "Insufficient balance"
        && Sanitizer.sanitize("4111111111111112") == "4111111111111112",
      passed: &passed,
      failed: &failed
    )

    print("22. local biometric span...")
    let log = TelemetryLog()
    let biometricClient = try? MeridianClient(baseURL: "http://127.0.0.1:9/api/v1", sessionId: "bio", telemetry: log)
    let biometric = await biometricClient?.resolveBiometricPrompt(sensorAvailable: false)
    let biometricSpan = log.spans().first { $0.name == "biometric.prompt" }
    let biometricEvent = log.events().first { $0.code == "SCA_FALLBACK" }
    check(
      "biometric prompt records duration and SCA fallback",
      biometric?.code == "SCA_FALLBACK" && biometricSpan?.status == "error" && (biometricSpan?.durationMillis ?? -1) >= 0
        && biometricEvent?.stage == "biometric" && !(biometricEvent?.message.contains(pan) ?? true),
      passed: &passed,
      failed: &failed
    )

    print("23. traceparent, spans, and corridor telemetry...")
    do {
      let server = try await CaptureServer()
      let wire = TelemetryLog()
      let client = try MeridianClient(
        baseURL: "http://127.0.0.1:\(server.port)/api/v1",
        sessionId: "trace-room",
        telemetry: wire
      )
      let catalog = try await client.getCatalog()
      let fallback = await client.resolveBiometricPrompt(sensorAvailable: false)
      let payment = try await client.submitPayment(
        recipientId: "northline-studio",
        amountMinor: 1000,
        method: .card,
        note: "Rent \(iban)",
        idempotencyKey: "idem-trace-1"
      )
      _ = try await client.getState()
      let first = await client.checkSessionHealth()
      let second = await client.checkSessionHealth()
      let captured = try await server.dump()
      await server.stop()

      let paths = Set(captured.map(\.path))
      let required = ["/api/v1/catalog", "/api/v1/payments", "/api/v1/session/health", "/api/v1/state"]
      let headersOk = required.allSatisfy { path in
        guard let header = captured.first(where: { $0.path == path })?.traceparent else { return false }
        return TraceIds.isTraceparent(header) && captured.first(where: { $0.path == path })?.session == "trace-room"
      }
      let paymentCapture = captured.first { $0.path == "/api/v1/payments" }
      let gateway = wire.spans().first { $0.name == "payment.gateway" }
      let parse = wire.spans().first { $0.name == "catalog.parse" }
      let headerMatchesSpan = gateway != nil && (paymentCapture?.traceparent?.contains(gateway!.traceId) ?? false)
        && (paymentCapture?.traceparent?.contains(gateway!.spanId) ?? false)
      let dump = (wire.events().map { "\($0.code) \($0.stage) \($0.message) \($0.attributes)" } + wire.spans().map { "\($0.attributes)" }).joined(separator: " ")
      let redacted = !dump.contains(pan) && !dump.contains(iban) && !dump.contains("GB82 WEST") && !dump.contains("unlisted")
      let corridor = wire.events().filter { $0.name == "corridor.degraded" }
      check(
        "W3C traceparent on catalog, payments, and session health",
        catalog.providers.isEmpty && paths.isSuperset(of: required) && headersOk && paymentCapture?.idempotency == "idem-trace-1"
          && (paymentCapture?.body.contains(iban) ?? false) && headerMatchesSpan
          && parse?.status == "ok" && (parse?.durationMillis ?? -1) >= 0
          && gateway?.status == "error" && (gateway?.durationMillis ?? -1) >= 0
          && fallback.code == "SCA_FALLBACK"
          && payment.code == "DECLINED" && !(payment.error?.contains(pan) ?? true) && !(payment.error?.contains("WEST") ?? true)
          && first.connection == "connected" && second.connection == "degraded"
          && second.corridors.contains { $0.id == "adyen-card" && $0.state == "degraded" }
          && second.corridors.contains { $0.id == "corridor" && $0.state == "down" }
          && corridor.count == 2
          && wire.events().contains { $0.code == "DECLINED" && $0.stage == "gateway" }
          && wire.events().contains { $0.name == "connection.state" && $0.attributes["connection"] == "degraded" }
          && redacted,
        passed: &passed,
        failed: &failed
      )
    } catch {
      print("  detail: \(error)")
      check("W3C traceparent on catalog, payments, and session health", false, passed: &passed, failed: &failed)
    }
  }
}

private struct CaptureRecord: Decodable {
  let path: String
  let traceparent: String?
  let session: String?
  let idempotency: String?
  let body: String
}

private actor CaptureServer {
  let port: Int
  private let process: Process

  init() async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = ["-c", CaptureServer.script]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let handle = output.fileHandleForReading
    var collected = Data()
    while true {
      let chunk = handle.availableData
      if chunk.isEmpty { throw CheckFailure("python server exited") }
      collected.append(chunk)
      if let text = String(data: collected, encoding: .utf8), let line = text.split(separator: "\n").first, line.hasPrefix("PORT ") {
        let number = Int(line.dropFirst(5))
        guard let number else { throw CheckFailure("missing port") }
        self.port = number
        self.process = process
        return
      }
    }
  }

  func dump() async throws -> [CaptureRecord] {
    let url = URL(string: "http://127.0.0.1:\(port)/__dump")!
    var request = URLRequest(url: url)
    request.timeoutInterval = 5
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw CheckFailure("dump failed")
    }
    return try JSONDecoder().decode([CaptureRecord].self, from: data)
  }

  func stop() async {
    guard let url = URL(string: "http://127.0.0.1:\(port)/__shutdown") else { return }
    var request = URLRequest(url: url)
    request.timeoutInterval = 5
    _ = try? await URLSession.shared.data(for: request)
    process.waitUntilExit()
  }

  private static let script = #"""
import json, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
captured = []
health_calls = {"n": 0}
lock = threading.Lock()

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def do_GET(self):
        self.route(b"")
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0") or "0")
        self.route(self.rfile.read(length) if length else b"")
    def do_PATCH(self):
        self.do_POST()
    def route(self, raw):
        path = self.path.split("?", 1)[0]
        if path == "/__dump":
            self._send(200, json.dumps(captured).encode())
            return
        if path == "/__shutdown":
            self._send(200, b"{}")
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return
        body = raw.decode("utf-8", "replace")
        with lock:
            if path.endswith("/session/health"):
                health_calls["n"] += 1
            attempt = health_calls["n"]
            captured.append({
                "path": path,
                "traceparent": self.headers.get("traceparent"),
                "session": self.headers.get("X-Rehearsal-Session"),
                "idempotency": self.headers.get("Idempotency-Key"),
                "body": body,
            })
        if path.endswith("/catalog"):
            payload = b'{"demoDate":"2026-09-18","recipients":[],"providers":[]}'
            status = 200
        elif path.endswith("/payments"):
            payload = b'{"ok":false,"code":"DECLINED","error":"declined 4111111111111111 GB82WEST12345698765432"}'
            status = 422
        elif path.endswith("/session/health"):
            if attempt == 1:
                payload = b'{"status":"UP","connection":"connected","corridors":[{"id":"adyen-card","state":"healthy"},{"id":"worldpay-bank","state":"healthy"}]}'
            else:
                payload = b'{"status":"UP","connection":"connected","corridors":[{"id":"adyen-card","state":"degraded"},{"id":"unlisted","state":"down"}]}'
            status = 200
        elif path.endswith("/state"):
            payload = b'{"version":1,"balance":1,"transactions":[],"budgets":[]}'
            status = 200
        else:
            payload = b"{}"
            status = 404
        self._send(status, payload)
    def _send(self, status, payload):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
    def log_message(self, fmt, *args):
        return

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
print("PORT %s" % server.server_address[1], flush=True)
server.serve_forever()
"""#

}

private struct CheckFailure: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}
