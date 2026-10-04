import Foundation

/// Local dogfood and canary gate for the mobile rehearsal.
/// Cohort math, error budget, settlement variance and rollback stay in-process.
/// Open incidents are an operator-supplied count. Store upload and provider calls stay outside this client.
/// Settlement figures are integer GBP pence.

public let rolloutWindowDays = 14
public let rolloutSampleFloor = 100
public let rolloutErrorBudgetPercent = 1
public let settlementCurrencyCode = "GBP"

public enum RolloutPhase: String, Equatable {
  case dogfood
  case percent5
  case percent25
  case percent50
  case percent100
  case rolledBack
}

public enum RolloutReason: String, Equatable {
  case withinThresholds = "WITHIN_THRESHOLDS"
  case advanced = "ADVANCED"
  case heldTelemetrySample = "HELD_TELEMETRY_SAMPLE"
  case heldRollbackUnverified = "HELD_ROLLBACK_UNVERIFIED"
  case heldDwell = "HELD_DWELL"
  case heldInvalidInput = "HELD_INVALID_INPUT"
  case rolledBackAlerts = "ROLLED_BACK_ALERTS"
  case rolledBackErrorBudget = "ROLLED_BACK_ERROR_BUDGET"
  case rolledBackSettlement = "ROLLED_BACK_SETTLEMENT"
  case stayRolledBack = "STAY_ROLLED_BACK"
}

public enum ReleaseChannel: String, Equatable {
  case dogfood
  case canary
}

public enum RolloutRing: String, Equatable {
  case staging
  case pilot
}

public enum PilotCorridor: String, CaseIterable, Equatable {
  case londonDublin = "london-dublin"
  case amsterdamFrankfurt = "amsterdam-frankfurt"
  case parisBrussels = "paris-brussels"

  public var displayName: String {
    switch self {
    case .londonDublin: return "London-Dublin"
    case .amsterdamFrankfurt: return "Amsterdam-Frankfurt"
    case .parisBrussels: return "Paris-Brussels"
    }
  }
}

public struct RolloutTelemetry: Equatable {
  public let requests: Int
  public let errors: Int
  /// Operator-supplied open incident count. This client does not contact an alerting vendor.
  public let openAlerts: Int
  public let expectedSettlementPence: Int
  public let actualSettlementPence: Int

  public init(
    requests: Int,
    errors: Int,
    openAlerts: Int,
    expectedSettlementPence: Int,
    actualSettlementPence: Int
  ) {
    self.requests = requests
    self.errors = errors
    self.openAlerts = openAlerts
    self.expectedSettlementPence = expectedSettlementPence
    self.actualSettlementPence = actualSettlementPence
  }
}

public struct RolloutSnapshot: Equatable {
  public let phase: RolloutPhase
  public let dayIndex: Int
  public let dwellDays: Int
  public let stagingRollbackVerified: Bool
  public let pilotRollbackVerified: Bool

  public init(
    phase: RolloutPhase,
    dayIndex: Int,
    dwellDays: Int,
    stagingRollbackVerified: Bool,
    pilotRollbackVerified: Bool
  ) {
    self.phase = phase
    self.dayIndex = dayIndex
    self.dwellDays = dwellDays
    self.stagingRollbackVerified = stagingRollbackVerified
    self.pilotRollbackVerified = pilotRollbackVerified
  }
}

public struct RolloutDecision: Equatable {
  public let phase: RolloutPhase
  public let canaryPercent: Int
  public let reason: RolloutReason
  public let settlementVariancePence: Int
  public let withinThresholds: Bool

  public init(
    phase: RolloutPhase,
    canaryPercent: Int,
    reason: RolloutReason,
    settlementVariancePence: Int,
    withinThresholds: Bool
  ) {
    self.phase = phase
    self.canaryPercent = canaryPercent
    self.reason = reason
    self.settlementVariancePence = settlementVariancePence
    self.withinThresholds = withinThresholds
  }
}

public struct DogfoodTrack: Equatable {
  public let platform: String
  public let track: String
  public let audience: String
  public let uploadPerformed: Bool

  public init(platform: String, track: String, audience: String, uploadPerformed: Bool) {
    self.platform = platform
    self.track = track
    self.audience = audience
    self.uploadPerformed = uploadPerformed
  }
}

public struct DogfoodPlan: Equatable {
  public let tracks: [DogfoodTrack]
  public let rehearsalOnly: Bool

  public init(tracks: [DogfoodTrack], rehearsalOnly: Bool) {
    self.tracks = tracks
    self.rehearsalOnly = rehearsalOnly
  }
}

public struct RollbackVerification: Equatable {
  public let ring: RolloutRing
  public let passed: Bool
  public let reason: RolloutReason
  public let canaryTrafficStopped: Bool
  public let dogfoodRemainsEligible: Bool
  public let liveEnvironment: Bool

  public init(
    ring: RolloutRing,
    passed: Bool,
    reason: RolloutReason,
    canaryTrafficStopped: Bool,
    dogfoodRemainsEligible: Bool,
    liveEnvironment: Bool
  ) {
    self.ring = ring
    self.passed = passed
    self.reason = reason
    self.canaryTrafficStopped = canaryTrafficStopped
    self.dogfoodRemainsEligible = dogfoodRemainsEligible
    self.liveEnvironment = liveEnvironment
  }
}

public func europeanPilotCorridors() -> [PilotCorridor] {
  PilotCorridor.allCases
}

public func internalDogfoodPlan() -> DogfoodPlan {
  DogfoodPlan(
    tracks: [
      DogfoodTrack(platform: "ios", track: "testflight-internal", audience: "internal-dogfood", uploadPerformed: false),
      DogfoodTrack(platform: "android", track: "play-internal-testing", audience: "internal-dogfood", uploadPerformed: false),
    ],
    rehearsalOnly: true
  )
}

public func canaryPercent(_ phase: RolloutPhase) -> Int {
  switch phase {
  case .dogfood, .rolledBack: return 0
  case .percent5: return 5
  case .percent25: return 25
  case .percent50: return 50
  case .percent100: return 100
  }
}

/// FNV-1a 32-bit over UTF-8, modulo 100. The same key always lands in the same cohort.
public func cohortBucket(_ key: String) -> Int {
  var hash: UInt32 = 2_166_136_261
  for byte in key.utf8 {
    hash ^= UInt32(byte)
    hash = hash &* 16_777_619
  }
  return Int(hash % 100)
}

/// Internal dogfood stays eligible so testers can keep diagnosing a rolled-back build.
/// Canary traffic follows the phase percent and is empty at 0.
public func trafficEligible(channel: ReleaseChannel, bucket: Int, phase: RolloutPhase) -> Bool {
  precondition((0...99).contains(bucket), "cohort bucket must be 0..99")
  switch channel {
  case .dogfood:
    return true
  case .canary:
    return bucket < canaryPercent(phase)
  }
}

public func healthyRolloutTelemetry() -> RolloutTelemetry {
  RolloutTelemetry(
    requests: 200,
    errors: 0,
    openAlerts: 0,
    expectedSettlementPence: 250_000,
    actualSettlementPence: 250_000
  )
}

public func settlementVariancePence(_ telemetry: RolloutTelemetry) -> Int {
  let delta = Int64(telemetry.actualSettlementPence) - Int64(telemetry.expectedSettlementPence)
  let absolute = delta < 0 ? -delta : delta
  return Int(absolute)
}

public func evaluateRollout(_ snapshot: RolloutSnapshot, telemetry: RolloutTelemetry) -> RolloutDecision {
  if inputInvalid(snapshot, telemetry) {
    return decision(snapshot.phase, .heldInvalidInput, 0, false)
  }
  let variance = settlementVariancePence(telemetry)
  let breach = breachReason(telemetry)
  if snapshot.phase == .rolledBack {
    return decision(.rolledBack, .stayRolledBack, variance, breach == nil)
  }
  if let breach {
    return decision(.rolledBack, breach, variance, false)
  }
  if !snapshot.stagingRollbackVerified || !snapshot.pilotRollbackVerified {
    return decision(snapshot.phase, .heldRollbackUnverified, variance, true)
  }
  if !metricsClear(telemetry) {
    return decision(snapshot.phase, .heldTelemetrySample, variance, true)
  }
  let ceiling = scheduledPhase(snapshot.dayIndex)
  if phaseRank(snapshot.phase) >= phaseRank(ceiling) {
    return decision(snapshot.phase, .withinThresholds, variance, true)
  }
  if snapshot.dwellDays < dwellRequired(snapshot.phase) {
    return decision(snapshot.phase, .heldDwell, variance, true)
  }
  return decision(nextPhase(snapshot.phase), .advanced, variance, true)
}

/// Walks the 14-day schedule one step at a time: 5% (days 0-3), 25% (days 4-7),
/// 50% (days 8-10), 100% (days 11-13). A breach on `breachOnDay` sticks for the rest of the window.
public func rehearseFourteenDayProgression(breachOnDay: Int? = nil) -> [RolloutDecision] {
  var decisions: [RolloutDecision] = []
  var phase = RolloutPhase.dogfood
  var enteredOn = 0
  for day in 0..<rolloutWindowDays {
    let telemetry: RolloutTelemetry
    if breachOnDay == day {
      telemetry = RolloutTelemetry(
        requests: 200,
        errors: 0,
        openAlerts: 1,
        expectedSettlementPence: 250_000,
        actualSettlementPence: 250_000
      )
    } else {
      telemetry = healthyRolloutTelemetry()
    }
    let decision = evaluateRollout(
      RolloutSnapshot(
        phase: phase,
        dayIndex: day,
        dwellDays: day - enteredOn,
        stagingRollbackVerified: true,
        pilotRollbackVerified: true
      ),
      telemetry: telemetry
    )
    decisions.append(decision)
    if decision.phase != phase {
      phase = decision.phase
      enteredOn = day
    }
  }
  return decisions
}

/// Staging injects an open incident at 5%. Pilot injects a 1 pence settlement mismatch at 25%.
/// Both run locally. `liveEnvironment` stays false.
public func verifyEmergencyRollback(ring: RolloutRing) -> RollbackVerification {
  let phase: RolloutPhase
  let telemetry: RolloutTelemetry
  let expectedReason: RolloutReason
  switch ring {
  case .staging:
    phase = .percent5
    telemetry = RolloutTelemetry(requests: 200, errors: 0, openAlerts: 1, expectedSettlementPence: 100_000, actualSettlementPence: 100_000)
    expectedReason = .rolledBackAlerts
  case .pilot:
    phase = .percent25
    telemetry = RolloutTelemetry(requests: 200, errors: 0, openAlerts: 0, expectedSettlementPence: 100_000, actualSettlementPence: 100_001)
    expectedReason = .rolledBackSettlement
  }
  let decision = evaluateRollout(
    RolloutSnapshot(
      phase: phase,
      dayIndex: 1,
      dwellDays: 1,
      stagingRollbackVerified: true,
      pilotRollbackVerified: true
    ),
    telemetry: telemetry
  )
  let canaryStopped = !trafficEligible(channel: .canary, bucket: 0, phase: decision.phase)
  let dogfoodOk = trafficEligible(channel: .dogfood, bucket: 0, phase: decision.phase)
  let passed = decision.phase == .rolledBack
    && decision.canaryPercent == 0
    && !decision.withinThresholds
    && canaryStopped
    && dogfoodOk
    && decision.reason == expectedReason
  return RollbackVerification(
    ring: ring,
    passed: passed,
    reason: decision.reason,
    canaryTrafficStopped: canaryStopped,
    dogfoodRemainsEligible: dogfoodOk,
    liveEnvironment: false
  )
}

private func decision(
  _ phase: RolloutPhase,
  _ reason: RolloutReason,
  _ variance: Int,
  _ withinThresholds: Bool
) -> RolloutDecision {
  RolloutDecision(
    phase: phase,
    canaryPercent: canaryPercent(phase),
    reason: reason,
    settlementVariancePence: variance,
    withinThresholds: withinThresholds
  )
}

private func inputInvalid(_ snapshot: RolloutSnapshot, _ telemetry: RolloutTelemetry) -> Bool {
  if snapshot.dayIndex < 0 || snapshot.dwellDays < 0 { return true }
  if telemetry.requests < 0 || telemetry.errors < 0 || telemetry.openAlerts < 0 { return true }
  if telemetry.errors > telemetry.requests { return true }
  if telemetry.expectedSettlementPence < 0 || telemetry.actualSettlementPence < 0 { return true }
  return false
}

private func breachReason(_ telemetry: RolloutTelemetry) -> RolloutReason? {
  if telemetry.openAlerts >= 1 { return .rolledBackAlerts }
  if settlementVariancePence(telemetry) != 0 { return .rolledBackSettlement }
  if telemetry.requests >= rolloutSampleFloor && overErrorBudget(telemetry) {
    return .rolledBackErrorBudget
  }
  return nil
}

private func metricsClear(_ telemetry: RolloutTelemetry) -> Bool {
  if telemetry.requests < rolloutSampleFloor { return false }
  if telemetry.openAlerts != 0 { return false }
  if settlementVariancePence(telemetry) != 0 { return false }
  return !overErrorBudget(telemetry)
}

private func overErrorBudget(_ telemetry: RolloutTelemetry) -> Bool {
  Int64(telemetry.errors) * 100 > Int64(telemetry.requests) * Int64(rolloutErrorBudgetPercent)
}

private func scheduledPhase(_ dayIndex: Int) -> RolloutPhase {
  switch dayIndex {
  case ...3: return .percent5
  case 4...7: return .percent25
  case 8...10: return .percent50
  default: return .percent100
  }
}

private func dwellRequired(_ phase: RolloutPhase) -> Int {
  switch phase {
  case .percent5: return 4
  case .percent25: return 4
  case .percent50: return 3
  default: return 0
  }
}

private func phaseRank(_ phase: RolloutPhase) -> Int {
  switch phase {
  case .dogfood: return 0
  case .percent5: return 1
  case .percent25: return 2
  case .percent50: return 3
  case .percent100: return 4
  case .rolledBack: return -1
  }
}

private func nextPhase(_ phase: RolloutPhase) -> RolloutPhase {
  switch phase {
  case .dogfood: return .percent5
  case .percent5: return .percent25
  case .percent25: return .percent50
  case .percent50: return .percent100
  case .percent100, .rolledBack: return phase
  }
}
