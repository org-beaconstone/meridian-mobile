import Foundation

/// Client-side metrics for the provider catalog lifecycle.
///
/// All diagnostic log lines are tagged with the `X-Rehearsal-Session` identifier
/// so they can be correlated with the server-side request trace.
public struct CatalogMetrics: Sendable {
  public private(set) var fetchSuccessCount: Int = 0
  public private(set) var fetchFailureCount: Int = 0
  public private(set) var unrecognizedProviderCount: Int = 0

  public init() {}

  /// Record a successful catalog fetch and emit a structured log line.
  public mutating func recordFetchSuccess(sessionId: String) {
    fetchSuccessCount += 1
    print(
      "[MeridianSDK] session=\(sessionId) event=catalog.fetch.success"
        + " total_success=\(fetchSuccessCount)"
    )
  }

  /// Record a failed catalog fetch and emit a structured log line.
  public mutating func recordFetchFailure(sessionId: String, error: Error) {
    fetchFailureCount += 1
    print(
      "[MeridianSDK] session=\(sessionId) event=catalog.fetch.failure"
        + " total_failure=\(fetchFailureCount)"
        + " error=\"\(error.localizedDescription)\""
    )
  }

  /// Record a single unrecognized provider identifier encountered in the catalog.
  public mutating func recordUnrecognizedProvider(id: String, sessionId: String) {
    unrecognizedProviderCount += 1
    print(
      "[MeridianSDK] session=\(sessionId) event=catalog.provider.unrecognized"
        + " provider_id=\(id)"
        + " total_unrecognized=\(unrecognizedProviderCount)"
    )
  }
}
