import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Tiny loopback HTTP server so rehearsal tests speak real HTTP rather than a stubbed URL loader.
final class LocalHTTPServer: @unchecked Sendable {
  private let lock = NSLock()
  private var socketFD: Int32 = -1
  private let handler: (String, [String: String], String) -> (Int, String)
  private(set) var port: UInt16 = 0

  init(handler: @escaping (String, [String: String], String) -> (Int, String)) throws {
    self.handler = handler
    signal(SIGPIPE, SIG_IGN)
    let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
    if fd < 0 { throw ServerError.failed("socket") }
    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(0).bigEndian
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    let bound = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    if bound != 0 { throw ServerError.failed("bind") }
    if listen(fd, 32) != 0 { throw ServerError.failed("listen") }
    var named = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let namedRC = withUnsafeMutablePointer(to: &named) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        getsockname(fd, $0, &length)
      }
    }
    if namedRC != 0 { throw ServerError.failed("getsockname") }
    port = UInt16(bigEndian: named.sin_port)
    socketFD = fd
    Thread.detachNewThread { [weak self] in
      self?.acceptLoop()
    }
  }

  func stop() {
    lock.lock()
    let fd = socketFD
    socketFD = -1
    lock.unlock()
    if fd >= 0 { close(fd) }
  }

  private func acceptLoop() {
    while true {
      lock.lock()
      let fd = socketFD
      lock.unlock()
      if fd < 0 { return }
      let client = accept(fd, nil, nil)
      if client < 0 { return }
      serve(client)
      close(client)
    }
  }

  private func serve(_ client: Int32) {
    guard let request = readRequest(client) else { return }
    let (status, body) = handler(request.start, request.headers, request.body)
    if status == 0 { return }
    let payload = Data(body.utf8)
    let header = "HTTP/1.1 \(status) \(reason(status))\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
    var bytes = Data(header.utf8)
    bytes.append(payload)
    bytes.withUnsafeBytes { raw in
      guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
      var sent = 0
      while sent < raw.count {
        let n = write(client, base.advanced(by: sent), raw.count - sent)
        if n <= 0 { return }
        sent += n
      }
    }
  }

  private func readRequest(_ client: Int32) -> (start: String, headers: [String: String], body: String)? {
    var buffer = Data()
    var tmp = [UInt8](repeating: 0, count: 8192)
    while buffer.range(of: Data("\r\n\r\n".utf8)) == nil {
      let n = read(client, &tmp, tmp.count)
      if n <= 0 { return nil }
      buffer.append(contentsOf: tmp.prefix(n))
      if buffer.count > 1_000_000 { return nil }
    }
    guard let split = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
    let headerText = String(data: buffer.subdata(in: 0..<split.lowerBound), encoding: .utf8) ?? ""
    let lines = headerText.components(separatedBy: "\r\n")
    guard let start = lines.first else { return nil }
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      guard let colon = line.firstIndex(of: ":") else { continue }
      let name = line[..<colon].lowercased()
      let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      headers[name] = value
    }
    let length = Int(headers["content-length"] ?? "0") ?? 0
    var body = buffer.subdata(in: split.upperBound..<buffer.count)
    while body.count < length {
      let n = read(client, &tmp, tmp.count)
      if n <= 0 { break }
      body.append(contentsOf: tmp.prefix(n))
    }
    let text = String(data: body.prefix(length), encoding: .utf8) ?? ""
    return (start, headers, text)
  }

  private func reason(_ status: Int) -> String {
    switch status {
    case 200: return "OK"
    case 202: return "Accepted"
    case 400: return "Bad Request"
    case 409: return "Conflict"
    case 422: return "Unprocessable Entity"
    case 503: return "Service Unavailable"
    default: return "OK"
    }
  }

  enum ServerError: Error { case failed(String) }
}
