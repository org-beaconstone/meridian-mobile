package com.atlassian.meridian

// MARK: - SCA Result

sealed class SCAResult {
    /** Authentication succeeded. */
    object Success : SCAResult()

    /** The user cancelled the prompt. */
    object Cancelled : SCAResult()

    /** Authentication failed or is unavailable. */
    data class Failed(val reason: String) : SCAResult()
}

// MARK: - SCA Challenge

sealed class SCAChallenge(val reason: String) {
    /** Require biometric authentication only (fingerprint / face). */
    class Biometric(reason: String) : SCAChallenge(reason)

    /** Require device PIN / password only. */
    class Pin(reason: String) : SCAChallenge(reason)

    /** Accept biometric falling back to device PIN (recommended). */
    class Any(reason: String) : SCAChallenge(reason)
}

// MARK: - SCA Authenticating Interface

/**
 * Abstract SCA authenticator so that callers remain testable without real hardware.
 *
 * Production implementations use `BiometricPrompt` (Android) or `LAContext` (iOS).
 * Pass a stub in unit tests.
 */
interface SCAAuthenticating {
    suspend fun authenticate(challenge: SCAChallenge): SCAResult
}

// MARK: - Test Stubs

/** Always succeeds – use in tests that should not depend on hardware. */
class AlwaysSucceedSCAHandler : SCAAuthenticating {
    override suspend fun authenticate(challenge: SCAChallenge): SCAResult = SCAResult.Success
}

/** Always fails – use in tests exercising error paths. */
class AlwaysFailSCAHandler(private val reason: String = "Test-induced failure") : SCAAuthenticating {
    override suspend fun authenticate(challenge: SCAChallenge): SCAResult = SCAResult.Failed(reason)
}

/** Always cancels – use in tests exercising cancellation paths. */
class AlwaysCancelSCAHandler : SCAAuthenticating {
    override suspend fun authenticate(challenge: SCAChallenge): SCAResult = SCAResult.Cancelled
}
