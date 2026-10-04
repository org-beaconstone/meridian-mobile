import Foundation
@testable import MeridianSDK

func runRolloutChecks(passed: inout Int, failed: inout Int) {
  func check(_ name: String, _ ok: Bool) {
    if ok {
      print("  ✓ \(name)")
      passed += 1
    } else {
      print("  ✗ \(name)")
      failed += 1
    }
  }

  print("21. cohort buckets...")
  check(
    "FNV-1a buckets",
    cohortBucket("") == 61
      && cohortBucket("a") == 20
      && cohortBucket("meridian-rehearsal") == 48
      && cohortBucket("london-dublin") == 0
      && cohortBucket("pilot-room-1") == 65
      && cohortBucket("meridian-rehearsal") == cohortBucket("meridian-rehearsal")
  )

  print("22. internal dogfood manifest...")
  let plan = internalDogfoodPlan()
  check(
    "TestFlight and Play internal tracks",
    plan.rehearsalOnly
      && plan.tracks.count == 2
      && plan.tracks[0].platform == "ios"
      && plan.tracks[0].track == "testflight-internal"
      && plan.tracks[0].audience == "internal-dogfood"
      && plan.tracks[0].uploadPerformed == false
      && plan.tracks[1].platform == "android"
      && plan.tracks[1].track == "play-internal-testing"
      && plan.tracks[1].uploadPerformed == false
  )

  print("23. European pilot corridors...")
  let codes = europeanPilotCorridors().map(\.rawValue)
  check(
    "three corridors settle in GBP",
    codes == ["london-dublin", "amsterdam-frankfurt", "paris-brussels"]
      && settlementCurrencyCode == "GBP"
      && rolloutWindowDays == 14
      && rolloutSampleFloor == 100
      && rolloutErrorBudgetPercent == 1
  )

  print("24. initial 5% canary...")
  let initial = evaluateRollout(verifiedSnapshot(.dogfood, 0, 0), telemetry: healthyRolloutTelemetry())
  check(
    "healthy dogfood advances to 5%",
    initial.phase == .percent5 && initial.canaryPercent == 5 && initial.reason == .advanced && initial.withinThresholds && initial.settlementVariancePence == 0
  )

  print("25. short telemetry sample...")
  let shortSample = evaluateRollout(
    verifiedSnapshot(.dogfood, 0, 0),
    telemetry: RolloutTelemetry(requests: 99, errors: 2, openAlerts: 0, expectedSettlementPence: 10_000, actualSettlementPence: 10_000)
  )
  check("sample under 100 holds", shortSample.phase == .dogfood && shortSample.reason == .heldTelemetrySample && shortSample.withinThresholds)

  print("26. rollback verification gate...")
  let unverified = evaluateRollout(
    RolloutSnapshot(phase: .dogfood, dayIndex: 0, dwellDays: 0, stagingRollbackVerified: false, pilotRollbackVerified: true),
    telemetry: healthyRolloutTelemetry()
  )
  check("unverified rollback stays on dogfood", unverified.phase == .dogfood && unverified.canaryPercent == 0 && unverified.reason == .heldRollbackUnverified)

  print("27. error budget...")
  let withinBudget = evaluateRollout(
    verifiedSnapshot(.dogfood, 0, 0),
    telemetry: RolloutTelemetry(requests: 100, errors: 1, openAlerts: 0, expectedSettlementPence: 10_000, actualSettlementPence: 10_000)
  )
  let overBudget = evaluateRollout(
    verifiedSnapshot(.percent5, 1, 1),
    telemetry: RolloutTelemetry(requests: 100, errors: 2, openAlerts: 0, expectedSettlementPence: 10_000, actualSettlementPence: 10_000)
  )
  check(
    "1% allowed and 2% rolls back",
    withinBudget.phase == .percent5
      && withinBudget.reason == .advanced
      && overBudget.phase == .rolledBack
      && overBudget.reason == .rolledBackErrorBudget
      && overBudget.withinThresholds == false
      && overBudget.canaryPercent == 0
  )

  print("28. open incident...")
  let alerted = evaluateRollout(
    verifiedSnapshot(.percent5, 1, 1),
    telemetry: RolloutTelemetry(requests: 10, errors: 0, openAlerts: 1, expectedSettlementPence: 10_000, actualSettlementPence: 10_000)
  )
  check("open incident rolls back", alerted.phase == .rolledBack && alerted.reason == .rolledBackAlerts && alerted.withinThresholds == false)

  print("29. settlement variance...")
  let mismatched = evaluateRollout(
    verifiedSnapshot(.percent25, 5, 1),
    telemetry: RolloutTelemetry(requests: 200, errors: 0, openAlerts: 0, expectedSettlementPence: 100_000, actualSettlementPence: 100_001)
  )
  check(
    "1 pence variance rolls back",
    mismatched.phase == .rolledBack && mismatched.reason == .rolledBackSettlement && mismatched.settlementVariancePence == 1 && mismatched.withinThresholds == false
  )

  print("30. dwell and schedule...")
  let early = evaluateRollout(verifiedSnapshot(.percent5, 3, 4), telemetry: healthyRolloutTelemetry())
  let shortDwell = evaluateRollout(verifiedSnapshot(.percent5, 4, 3), telemetry: healthyRolloutTelemetry())
  let stepped = evaluateRollout(verifiedSnapshot(.percent5, 4, 4), telemetry: healthyRolloutTelemetry())
  check(
    "schedule and dwell gate 25%",
    early.phase == .percent5
      && early.reason == .withinThresholds
      && shortDwell.phase == .percent5
      && shortDwell.reason == .heldDwell
      && stepped.phase == .percent25
      && stepped.canaryPercent == 25
      && stepped.reason == .advanced
  )

  print("31. single-step advance...")
  let skipped = evaluateRollout(verifiedSnapshot(.dogfood, 11, 0), telemetry: healthyRolloutTelemetry())
  check("day 11 from dogfood lands on 5%", skipped.phase == .percent5 && skipped.canaryPercent == 5 && skipped.reason == .advanced)

  print("32. fourteen-day progression...")
  let run = rehearseFourteenDayProgression()
  check(
    "5 to 25 to 50 to 100",
    run.count == 14
      && run.map(\.canaryPercent) == [5, 5, 5, 5, 25, 25, 25, 25, 50, 50, 50, 100, 100, 100]
      && run[0].reason == .advanced
      && run[1].reason == .withinThresholds
      && run[4].reason == .advanced
      && run[8].reason == .advanced
      && run[11].reason == .advanced
      && run.allSatisfy(\.withinThresholds)
      && run.allSatisfy { $0.settlementVariancePence == 0 }
  )

  print("33. breach sticks...")
  let breached = rehearseFourteenDayProgression(breachOnDay: 6)
  check(
    "rollback holds through day 14",
    breached[5].canaryPercent == 25
      && breached[6].phase == .rolledBack
      && breached[6].reason == .rolledBackAlerts
      && breached[6].withinThresholds == false
      && breached[7].reason == .stayRolledBack
      && breached[7].withinThresholds
      && breached[13].phase == .rolledBack
      && breached[13].canaryPercent == 0
  )

  print("34. emergency rollback rings...")
  let staging = verifyEmergencyRollback(ring: .staging)
  let pilot = verifyEmergencyRollback(ring: .pilot)
  check(
    "staging incident and pilot settlement",
    staging.ring == .staging
      && staging.passed
      && staging.reason == .rolledBackAlerts
      && staging.canaryTrafficStopped
      && staging.dogfoodRemainsEligible
      && staging.liveEnvironment == false
      && pilot.ring == .pilot
      && pilot.passed
      && pilot.reason == .rolledBackSettlement
      && pilot.canaryTrafficStopped
      && pilot.dogfoodRemainsEligible
      && pilot.liveEnvironment == false
  )

  print("35. cohort eligibility...")
  check(
    "percent boundaries",
    trafficEligible(channel: .canary, bucket: 0, phase: .percent5)
      && trafficEligible(channel: .canary, bucket: 4, phase: .percent5)
      && trafficEligible(channel: .canary, bucket: 5, phase: .percent5) == false
      && trafficEligible(channel: .canary, bucket: 48, phase: .percent25) == false
      && trafficEligible(channel: .canary, bucket: 48, phase: .percent50)
      && trafficEligible(channel: .canary, bucket: 99, phase: .percent100)
      && trafficEligible(channel: .canary, bucket: 0, phase: .dogfood) == false
      && trafficEligible(channel: .canary, bucket: 0, phase: .rolledBack) == false
      && trafficEligible(channel: .dogfood, bucket: 48, phase: .rolledBack)
  )

  print("36. invalid telemetry...")
  let negative = evaluateRollout(
    verifiedSnapshot(.percent5, 1, 1),
    telemetry: RolloutTelemetry(requests: -1, errors: 0, openAlerts: 0, expectedSettlementPence: 10, actualSettlementPence: 10)
  )
  let badDay = evaluateRollout(
    verifiedSnapshot(.percent25, -1, 0),
    telemetry: healthyRolloutTelemetry()
  )
  check(
    "invalid input keeps the current phase",
    negative.phase == .percent5
      && negative.reason == .heldInvalidInput
      && negative.withinThresholds == false
      && badDay.phase == .percent25
      && badDay.reason == .heldInvalidInput
  )
}

private func verifiedSnapshot(_ phase: RolloutPhase, _ day: Int, _ dwell: Int) -> RolloutSnapshot {
  RolloutSnapshot(
    phase: phase,
    dayIndex: day,
    dwellDays: dwell,
    stagingRollbackVerified: true,
    pilotRollbackVerified: true
  )
}
