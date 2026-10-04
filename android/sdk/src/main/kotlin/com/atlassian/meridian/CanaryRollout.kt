package com.atlassian.meridian

/**
 * Local dogfood and canary gate for the mobile rehearsal.
 * Cohort math, error budget, settlement variance and rollback stay in-process.
 * Open incidents are an operator-supplied count. Store upload and provider calls stay outside this client.
 * Settlement figures are integer GBP pence.
 */
const val rolloutWindowDays = 14
const val rolloutSampleFloor = 100
const val rolloutErrorBudgetPercent = 1
const val settlementCurrencyCode = "GBP"

enum class RolloutPhase {
  DOGFOOD,
  PERCENT_5,
  PERCENT_25,
  PERCENT_50,
  PERCENT_100,
  ROLLED_BACK,
}

enum class RolloutReason {
  WITHIN_THRESHOLDS,
  ADVANCED,
  HELD_TELEMETRY_SAMPLE,
  HELD_ROLLBACK_UNVERIFIED,
  HELD_DWELL,
  HELD_INVALID_INPUT,
  ROLLED_BACK_ALERTS,
  ROLLED_BACK_ERROR_BUDGET,
  ROLLED_BACK_SETTLEMENT,
  STAY_ROLLED_BACK,
}

enum class ReleaseChannel {
  DOGFOOD,
  CANARY,
}

enum class RolloutRing {
  STAGING,
  PILOT,
}

enum class PilotCorridor(val code: String, val displayName: String) {
  LONDON_DUBLIN("london-dublin", "London-Dublin"),
  AMSTERDAM_FRANKFURT("amsterdam-frankfurt", "Amsterdam-Frankfurt"),
  PARIS_BRUSSELS("paris-brussels", "Paris-Brussels"),
}

data class RolloutTelemetry(
  val requests: Int,
  val errors: Int,
  /** Operator-supplied open incident count. This client does not contact an alerting vendor. */
  val openAlerts: Int,
  val expectedSettlementPence: Int,
  val actualSettlementPence: Int,
)

data class RolloutSnapshot(
  val phase: RolloutPhase,
  val dayIndex: Int,
  val dwellDays: Int,
  val stagingRollbackVerified: Boolean,
  val pilotRollbackVerified: Boolean,
)

data class RolloutDecision(
  val phase: RolloutPhase,
  val canaryPercent: Int,
  val reason: RolloutReason,
  val settlementVariancePence: Int,
  val withinThresholds: Boolean,
)

data class DogfoodTrack(
  val platform: String,
  val track: String,
  val audience: String,
  val uploadPerformed: Boolean,
)

data class DogfoodPlan(
  val tracks: List<DogfoodTrack>,
  val rehearsalOnly: Boolean,
)

data class RollbackVerification(
  val ring: RolloutRing,
  val passed: Boolean,
  val reason: RolloutReason,
  val canaryTrafficStopped: Boolean,
  val dogfoodRemainsEligible: Boolean,
  val liveEnvironment: Boolean,
)

fun europeanPilotCorridors(): List<PilotCorridor> = PilotCorridor.values().toList()

fun internalDogfoodPlan(): DogfoodPlan = DogfoodPlan(
  tracks = listOf(
    DogfoodTrack(
      platform = "ios",
      track = "testflight-internal",
      audience = "internal-dogfood",
      uploadPerformed = false,
    ),
    DogfoodTrack(
      platform = "android",
      track = "play-internal-testing",
      audience = "internal-dogfood",
      uploadPerformed = false,
    ),
  ),
  rehearsalOnly = true,
)

fun canaryPercent(phase: RolloutPhase): Int = when (phase) {
  RolloutPhase.DOGFOOD, RolloutPhase.ROLLED_BACK -> 0
  RolloutPhase.PERCENT_5 -> 5
  RolloutPhase.PERCENT_25 -> 25
  RolloutPhase.PERCENT_50 -> 50
  RolloutPhase.PERCENT_100 -> 100
}

/** FNV-1a 32-bit over UTF-8, modulo 100. The same key always lands in the same cohort. */
fun cohortBucket(key: String): Int {
  var hash = 2166136261u
  for (byte in key.encodeToByteArray()) {
    hash = hash xor byte.toUByte().toUInt()
    hash *= 16777619u
  }
  return (hash % 100u).toInt()
}

/**
 * Internal dogfood stays eligible so testers can keep diagnosing a rolled-back build.
 * Canary traffic follows the phase percent and is empty at 0.
 */
fun trafficEligible(channel: ReleaseChannel, bucket: Int, phase: RolloutPhase): Boolean {
  require(bucket in 0..99) { "cohort bucket must be 0..99" }
  return when (channel) {
    ReleaseChannel.DOGFOOD -> true
    ReleaseChannel.CANARY -> bucket < canaryPercent(phase)
  }
}

fun healthyRolloutTelemetry(): RolloutTelemetry = RolloutTelemetry(
  requests = 200,
  errors = 0,
  openAlerts = 0,
  expectedSettlementPence = 250_000,
  actualSettlementPence = 250_000,
)

fun settlementVariancePence(telemetry: RolloutTelemetry): Int {
  val delta = telemetry.actualSettlementPence.toLong() - telemetry.expectedSettlementPence.toLong()
  val absolute = if (delta < 0) -delta else delta
  return absolute.toInt()
}

fun evaluateRollout(snapshot: RolloutSnapshot, telemetry: RolloutTelemetry): RolloutDecision {
  if (inputInvalid(snapshot, telemetry)) {
    return decision(snapshot.phase, RolloutReason.HELD_INVALID_INPUT, 0, false)
  }
  val variance = settlementVariancePence(telemetry)
  val breach = breachReason(telemetry)
  if (snapshot.phase == RolloutPhase.ROLLED_BACK) {
    return decision(RolloutPhase.ROLLED_BACK, RolloutReason.STAY_ROLLED_BACK, variance, breach == null)
  }
  if (breach != null) {
    return decision(RolloutPhase.ROLLED_BACK, breach, variance, false)
  }
  if (!snapshot.stagingRollbackVerified || !snapshot.pilotRollbackVerified) {
    return decision(snapshot.phase, RolloutReason.HELD_ROLLBACK_UNVERIFIED, variance, true)
  }
  if (!metricsClear(telemetry)) {
    return decision(snapshot.phase, RolloutReason.HELD_TELEMETRY_SAMPLE, variance, true)
  }
  val ceiling = scheduledPhase(snapshot.dayIndex)
  if (phaseRank(snapshot.phase) >= phaseRank(ceiling)) {
    return decision(snapshot.phase, RolloutReason.WITHIN_THRESHOLDS, variance, true)
  }
  if (snapshot.dwellDays < dwellRequired(snapshot.phase)) {
    return decision(snapshot.phase, RolloutReason.HELD_DWELL, variance, true)
  }
  return decision(nextPhase(snapshot.phase), RolloutReason.ADVANCED, variance, true)
}

/**
 * Walks the 14-day schedule one step at a time: 5% (days 0-3), 25% (days 4-7),
 * 50% (days 8-10), 100% (days 11-13). A breach on [breachOnDay] sticks for the rest of the window.
 */
fun rehearseFourteenDayProgression(breachOnDay: Int? = null): List<RolloutDecision> {
  val decisions = mutableListOf<RolloutDecision>()
  var phase = RolloutPhase.DOGFOOD
  var enteredOn = 0
  for (day in 0 until rolloutWindowDays) {
    val telemetry = if (breachOnDay != null && day == breachOnDay) {
      healthyRolloutTelemetry().copy(openAlerts = 1)
    } else {
      healthyRolloutTelemetry()
    }
    val decision = evaluateRollout(
      RolloutSnapshot(
        phase = phase,
        dayIndex = day,
        dwellDays = day - enteredOn,
        stagingRollbackVerified = true,
        pilotRollbackVerified = true,
      ),
      telemetry,
    )
    decisions += decision
    if (decision.phase != phase) {
      phase = decision.phase
      enteredOn = day
    }
  }
  return decisions
}

/**
 * Staging injects an open incident at 5%. Pilot injects a 1 pence settlement mismatch at 25%.
 * Both run locally. [RollbackVerification.liveEnvironment] stays false.
 */
fun verifyEmergencyRollback(ring: RolloutRing): RollbackVerification {
  val phase: RolloutPhase
  val telemetry: RolloutTelemetry
  val expectedReason: RolloutReason
  when (ring) {
    RolloutRing.STAGING -> {
      phase = RolloutPhase.PERCENT_5
      telemetry = RolloutTelemetry(200, 0, 1, 100_000, 100_000)
      expectedReason = RolloutReason.ROLLED_BACK_ALERTS
    }
    RolloutRing.PILOT -> {
      phase = RolloutPhase.PERCENT_25
      telemetry = RolloutTelemetry(200, 0, 0, 100_000, 100_001)
      expectedReason = RolloutReason.ROLLED_BACK_SETTLEMENT
    }
  }
  val decision = evaluateRollout(
    RolloutSnapshot(
      phase = phase,
      dayIndex = 1,
      dwellDays = 1,
      stagingRollbackVerified = true,
      pilotRollbackVerified = true,
    ),
    telemetry,
  )
  val canaryStopped = !trafficEligible(ReleaseChannel.CANARY, 0, decision.phase)
  val dogfoodOk = trafficEligible(ReleaseChannel.DOGFOOD, 0, decision.phase)
  val passed = decision.phase == RolloutPhase.ROLLED_BACK &&
    decision.canaryPercent == 0 &&
    !decision.withinThresholds &&
    canaryStopped &&
    dogfoodOk &&
    decision.reason == expectedReason
  return RollbackVerification(
    ring = ring,
    passed = passed,
    reason = decision.reason,
    canaryTrafficStopped = canaryStopped,
    dogfoodRemainsEligible = dogfoodOk,
    liveEnvironment = false,
  )
}

private fun decision(
  phase: RolloutPhase,
  reason: RolloutReason,
  variance: Int,
  withinThresholds: Boolean,
): RolloutDecision = RolloutDecision(
  phase = phase,
  canaryPercent = canaryPercent(phase),
  reason = reason,
  settlementVariancePence = variance,
  withinThresholds = withinThresholds,
)

private fun inputInvalid(snapshot: RolloutSnapshot, telemetry: RolloutTelemetry): Boolean {
  if (snapshot.dayIndex < 0 || snapshot.dwellDays < 0) return true
  if (telemetry.requests < 0 || telemetry.errors < 0 || telemetry.openAlerts < 0) return true
  if (telemetry.errors > telemetry.requests) return true
  if (telemetry.expectedSettlementPence < 0 || telemetry.actualSettlementPence < 0) return true
  return false
}

private fun breachReason(telemetry: RolloutTelemetry): RolloutReason? {
  if (telemetry.openAlerts >= 1) return RolloutReason.ROLLED_BACK_ALERTS
  if (settlementVariancePence(telemetry) != 0) return RolloutReason.ROLLED_BACK_SETTLEMENT
  if (telemetry.requests >= rolloutSampleFloor && overErrorBudget(telemetry)) {
    return RolloutReason.ROLLED_BACK_ERROR_BUDGET
  }
  return null
}

private fun metricsClear(telemetry: RolloutTelemetry): Boolean {
  if (telemetry.requests < rolloutSampleFloor) return false
  if (telemetry.openAlerts != 0) return false
  if (settlementVariancePence(telemetry) != 0) return false
  return !overErrorBudget(telemetry)
}

private fun overErrorBudget(telemetry: RolloutTelemetry): Boolean {
  return telemetry.errors.toLong() * 100 > telemetry.requests.toLong() * rolloutErrorBudgetPercent.toLong()
}

private fun scheduledPhase(dayIndex: Int): RolloutPhase = when {
  dayIndex <= 3 -> RolloutPhase.PERCENT_5
  dayIndex <= 7 -> RolloutPhase.PERCENT_25
  dayIndex <= 10 -> RolloutPhase.PERCENT_50
  else -> RolloutPhase.PERCENT_100
}

private fun dwellRequired(phase: RolloutPhase): Int = when (phase) {
  RolloutPhase.PERCENT_5 -> 4
  RolloutPhase.PERCENT_25 -> 4
  RolloutPhase.PERCENT_50 -> 3
  else -> 0
}

private fun phaseRank(phase: RolloutPhase): Int = when (phase) {
  RolloutPhase.DOGFOOD -> 0
  RolloutPhase.PERCENT_5 -> 1
  RolloutPhase.PERCENT_25 -> 2
  RolloutPhase.PERCENT_50 -> 3
  RolloutPhase.PERCENT_100 -> 4
  RolloutPhase.ROLLED_BACK -> -1
}

private fun nextPhase(phase: RolloutPhase): RolloutPhase = when (phase) {
  RolloutPhase.DOGFOOD -> RolloutPhase.PERCENT_5
  RolloutPhase.PERCENT_5 -> RolloutPhase.PERCENT_25
  RolloutPhase.PERCENT_25 -> RolloutPhase.PERCENT_50
  RolloutPhase.PERCENT_50 -> RolloutPhase.PERCENT_100
  else -> phase
}
