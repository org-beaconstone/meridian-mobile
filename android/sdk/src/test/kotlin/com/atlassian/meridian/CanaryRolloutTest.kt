package com.atlassian.meridian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CanaryRolloutTest {
  @Test
  fun testCohortBucketMatchesFnv1a() {
    assertEquals(61, cohortBucket(""))
    assertEquals(20, cohortBucket("a"))
    assertEquals(48, cohortBucket("meridian-rehearsal"))
    assertEquals(0, cohortBucket("london-dublin"))
    assertEquals(65, cohortBucket("pilot-room-1"))
    assertEquals(cohortBucket("meridian-rehearsal"), cohortBucket("meridian-rehearsal"))
  }

  @Test
  fun testInternalDogfoodManifest() {
    val plan = internalDogfoodPlan()
    assertTrue(plan.rehearsalOnly)
    assertEquals(2, plan.tracks.size)
    assertEquals("ios", plan.tracks[0].platform)
    assertEquals("testflight-internal", plan.tracks[0].track)
    assertEquals("internal-dogfood", plan.tracks[0].audience)
    assertFalse(plan.tracks[0].uploadPerformed)
    assertEquals("android", plan.tracks[1].platform)
    assertEquals("play-internal-testing", plan.tracks[1].track)
    assertEquals("internal-dogfood", plan.tracks[1].audience)
    assertFalse(plan.tracks[1].uploadPerformed)
  }

  @Test
  fun testEuropeanPilotCorridorsSettleInGbp() {
    assertEquals(
      listOf("london-dublin", "amsterdam-frankfurt", "paris-brussels"),
      europeanPilotCorridors().map { it.code },
    )
    assertEquals("GBP", settlementCurrencyCode)
    assertEquals(14, rolloutWindowDays)
    assertEquals(100, rolloutSampleFloor)
    assertEquals(1, rolloutErrorBudgetPercent)
  }

  @Test
  fun testInitialCanaryAdvancesOnHealthyTelemetry() {
    val decision = evaluateRollout(verifiedSnapshot(RolloutPhase.DOGFOOD, day = 0, dwell = 0), healthyRolloutTelemetry())
    assertEquals(RolloutPhase.PERCENT_5, decision.phase)
    assertEquals(5, decision.canaryPercent)
    assertEquals(RolloutReason.ADVANCED, decision.reason)
    assertEquals(0, decision.settlementVariancePence)
    assertTrue(decision.withinThresholds)
  }

  @Test
  fun testShortSampleHoldsProgression() {
    val decision = evaluateRollout(
      verifiedSnapshot(RolloutPhase.DOGFOOD, day = 0, dwell = 0),
      RolloutTelemetry(99, 2, 0, 10_000, 10_000),
    )
    assertEquals(RolloutPhase.DOGFOOD, decision.phase)
    assertEquals(RolloutReason.HELD_TELEMETRY_SAMPLE, decision.reason)
    assertTrue(decision.withinThresholds)
  }

  @Test
  fun testUnverifiedRollbackBlocksPromotion() {
    val decision = evaluateRollout(
      RolloutSnapshot(RolloutPhase.DOGFOOD, 0, 0, stagingRollbackVerified = false, pilotRollbackVerified = true),
      healthyRolloutTelemetry(),
    )
    assertEquals(RolloutPhase.DOGFOOD, decision.phase)
    assertEquals(0, decision.canaryPercent)
    assertEquals(RolloutReason.HELD_ROLLBACK_UNVERIFIED, decision.reason)
  }

  @Test
  fun testErrorBudgetBoundary() {
    val within = evaluateRollout(
      verifiedSnapshot(RolloutPhase.DOGFOOD, day = 0, dwell = 0),
      RolloutTelemetry(100, 1, 0, 10_000, 10_000),
    )
    assertEquals(RolloutPhase.PERCENT_5, within.phase)
    assertEquals(RolloutReason.ADVANCED, within.reason)

    val breach = evaluateRollout(
      verifiedSnapshot(RolloutPhase.PERCENT_5, day = 1, dwell = 1),
      RolloutTelemetry(100, 2, 0, 10_000, 10_000),
    )
    assertEquals(RolloutPhase.ROLLED_BACK, breach.phase)
    assertEquals(RolloutReason.ROLLED_BACK_ERROR_BUDGET, breach.reason)
    assertFalse(breach.withinThresholds)
    assertEquals(0, breach.canaryPercent)
  }

  @Test
  fun testOpenAlertRollsBack() {
    val decision = evaluateRollout(
      verifiedSnapshot(RolloutPhase.PERCENT_5, day = 1, dwell = 1),
      RolloutTelemetry(10, 0, 1, 10_000, 10_000),
    )
    assertEquals(RolloutPhase.ROLLED_BACK, decision.phase)
    assertEquals(RolloutReason.ROLLED_BACK_ALERTS, decision.reason)
    assertFalse(decision.withinThresholds)
  }

  @Test
  fun testSettlementVarianceRollsBack() {
    val decision = evaluateRollout(
      verifiedSnapshot(RolloutPhase.PERCENT_25, day = 5, dwell = 1),
      RolloutTelemetry(200, 0, 0, 100_000, 100_001),
    )
    assertEquals(RolloutPhase.ROLLED_BACK, decision.phase)
    assertEquals(RolloutReason.ROLLED_BACK_SETTLEMENT, decision.reason)
    assertEquals(1, decision.settlementVariancePence)
    assertFalse(decision.withinThresholds)
  }

  @Test
  fun testDwellAndSchedule() {
    val early = evaluateRollout(
      verifiedSnapshot(RolloutPhase.PERCENT_5, day = 3, dwell = 4),
      healthyRolloutTelemetry(),
    )
    assertEquals(RolloutPhase.PERCENT_5, early.phase)
    assertEquals(RolloutReason.WITHIN_THRESHOLDS, early.reason)

    val shortDwell = evaluateRollout(
      verifiedSnapshot(RolloutPhase.PERCENT_5, day = 4, dwell = 3),
      healthyRolloutTelemetry(),
    )
    assertEquals(RolloutPhase.PERCENT_5, shortDwell.phase)
    assertEquals(RolloutReason.HELD_DWELL, shortDwell.reason)

    val advanced = evaluateRollout(
      verifiedSnapshot(RolloutPhase.PERCENT_5, day = 4, dwell = 4),
      healthyRolloutTelemetry(),
    )
    assertEquals(RolloutPhase.PERCENT_25, advanced.phase)
    assertEquals(25, advanced.canaryPercent)
    assertEquals(RolloutReason.ADVANCED, advanced.reason)
  }

  @Test
  fun testCannotSkipPhases() {
    val decision = evaluateRollout(
      verifiedSnapshot(RolloutPhase.DOGFOOD, day = 11, dwell = 0),
      healthyRolloutTelemetry(),
    )
    assertEquals(RolloutPhase.PERCENT_5, decision.phase)
    assertEquals(5, decision.canaryPercent)
    assertEquals(RolloutReason.ADVANCED, decision.reason)
  }

  @Test
  fun testFourteenDayProgression() {
    val run = rehearseFourteenDayProgression()
    assertEquals(14, run.size)
    assertEquals(listOf(5, 5, 5, 5, 25, 25, 25, 25, 50, 50, 50, 100, 100, 100), run.map { it.canaryPercent })
    assertEquals(RolloutReason.ADVANCED, run[0].reason)
    assertEquals(RolloutReason.WITHIN_THRESHOLDS, run[1].reason)
    assertEquals(RolloutReason.ADVANCED, run[4].reason)
    assertEquals(RolloutReason.ADVANCED, run[8].reason)
    assertEquals(RolloutReason.ADVANCED, run[11].reason)
    assertTrue(run.all { it.withinThresholds })
    assertTrue(run.all { it.settlementVariancePence == 0 })
  }

  @Test
  fun testBreachStaysRolledBack() {
    val run = rehearseFourteenDayProgression(breachOnDay = 6)
    assertEquals(25, run[5].canaryPercent)
    assertEquals(RolloutPhase.ROLLED_BACK, run[6].phase)
    assertEquals(RolloutReason.ROLLED_BACK_ALERTS, run[6].reason)
    assertFalse(run[6].withinThresholds)
    assertEquals(RolloutReason.STAY_ROLLED_BACK, run[7].reason)
    assertTrue(run[7].withinThresholds)
    assertEquals(0, run[13].canaryPercent)
    assertEquals(RolloutPhase.ROLLED_BACK, run[13].phase)
  }

  @Test
  fun testEmergencyRollbackStagingAndPilot() {
    val staging = verifyEmergencyRollback(RolloutRing.STAGING)
    assertEquals(RolloutRing.STAGING, staging.ring)
    assertTrue(staging.passed)
    assertEquals(RolloutReason.ROLLED_BACK_ALERTS, staging.reason)
    assertTrue(staging.canaryTrafficStopped)
    assertTrue(staging.dogfoodRemainsEligible)
    assertFalse(staging.liveEnvironment)

    val pilot = verifyEmergencyRollback(RolloutRing.PILOT)
    assertEquals(RolloutRing.PILOT, pilot.ring)
    assertTrue(pilot.passed)
    assertEquals(RolloutReason.ROLLED_BACK_SETTLEMENT, pilot.reason)
    assertTrue(pilot.canaryTrafficStopped)
    assertTrue(pilot.dogfoodRemainsEligible)
    assertFalse(pilot.liveEnvironment)
  }

  @Test
  fun testCanaryEligibility() {
    assertTrue(trafficEligible(ReleaseChannel.CANARY, 0, RolloutPhase.PERCENT_5))
    assertTrue(trafficEligible(ReleaseChannel.CANARY, 4, RolloutPhase.PERCENT_5))
    assertFalse(trafficEligible(ReleaseChannel.CANARY, 5, RolloutPhase.PERCENT_5))
    assertFalse(trafficEligible(ReleaseChannel.CANARY, 48, RolloutPhase.PERCENT_25))
    assertTrue(trafficEligible(ReleaseChannel.CANARY, 48, RolloutPhase.PERCENT_50))
    assertTrue(trafficEligible(ReleaseChannel.CANARY, 99, RolloutPhase.PERCENT_100))
    assertFalse(trafficEligible(ReleaseChannel.CANARY, 0, RolloutPhase.DOGFOOD))
    assertFalse(trafficEligible(ReleaseChannel.CANARY, 0, RolloutPhase.ROLLED_BACK))
    assertTrue(trafficEligible(ReleaseChannel.DOGFOOD, 48, RolloutPhase.ROLLED_BACK))
    assertEquals(48, cohortBucket("meridian-rehearsal"))
  }

  @Test
  fun testInvalidTelemetryHoldsPhase() {
    val negative = evaluateRollout(
      verifiedSnapshot(RolloutPhase.PERCENT_5, day = 1, dwell = 1),
      RolloutTelemetry(-1, 0, 0, 10, 10),
    )
    assertEquals(RolloutPhase.PERCENT_5, negative.phase)
    assertEquals(RolloutReason.HELD_INVALID_INPUT, negative.reason)
    assertFalse(negative.withinThresholds)

    val badDay = evaluateRollout(
      verifiedSnapshot(RolloutPhase.PERCENT_25, day = -1, dwell = 0),
      healthyRolloutTelemetry(),
    )
    assertEquals(RolloutPhase.PERCENT_25, badDay.phase)
    assertEquals(RolloutReason.HELD_INVALID_INPUT, badDay.reason)
  }

  private fun verifiedSnapshot(phase: RolloutPhase, day: Int, dwell: Int) = RolloutSnapshot(
    phase = phase,
    dayIndex = day,
    dwellDays = dwell,
    stagingRollbackVerified = true,
    pilotRollbackVerified = true,
  )
}
