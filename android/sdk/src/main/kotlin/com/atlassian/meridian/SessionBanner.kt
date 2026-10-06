package com.atlassian.meridian

/**
 * Represents all valid states a payment-screen session banner can display.
 *
 * The sealed class maps to the four states defined in the Figma spec:
 * - [Active] – session confirmed valid on this device
 * - [Expiring] – session close to expiry; carries remaining seconds for countdown
 * - [ActiveElsewhere] – session active on a different device
 * - [SignedOut] – session has been terminated
 *
 * All recovery states preserve entered payment context by design: the banner
 * is non-blocking and does not clear form fields.
 */
sealed class SessionState {
  object Active : SessionState()
  data class Expiring(val secondsRemaining: Int) : SessionState()
  object ActiveElsewhere : SessionState()
  object SignedOut : SessionState()

  // -------------------------------------------------------------------------
  // Display helpers – used by both the Compose UI and accessibility layer
  // -------------------------------------------------------------------------

  /**
   * Short label announced by TalkBack when the banner state changes.
   * Satisfies the "native accessibility / TalkBack" acceptance criterion.
   */
  val accessibilityLabel: String
    get() = when (this) {
      is Active -> "Session active"
      is Expiring -> {
        val mins = secondsRemaining / 60
        val secs = secondsRemaining % 60
        if (mins > 0) {
          "Session expiring in $mins minute${if (mins == 1) "" else "s"} $secs second${if (secs == 1) "" else "s"}"
        } else {
          "Session expiring in $secondsRemaining second${if (secondsRemaining == 1) "" else "s"}"
        }
      }
      is ActiveElsewhere -> "Session active on another device"
      is SignedOut -> "Session signed out"
    }

  /**
   * Body text displayed inside the banner.
   */
  val message: String
    get() = when (this) {
      is Active -> "Your session is secure and active."
      is Expiring -> {
        val mins = secondsRemaining / 60
        val secs = secondsRemaining % 60
        if (mins > 0) {
          "Session expiring in ${mins}m ${secs}s. Tap Refresh to stay signed in."
        } else {
          "Session expiring in ${secondsRemaining}s. Tap Refresh to stay signed in."
        }
      }
      is ActiveElsewhere ->
        "Your session is active on another device. Your payment details are preserved. Sign in again to continue."
      is SignedOut ->
        "You have been signed out. Your payment details are preserved. Sign in again to continue."
    }

  /**
   * Whether this state exposes a primary action button.
   */
  val hasAction: Boolean
    get() = when (this) {
      is Active -> false
      is Expiring, is ActiveElsewhere, is SignedOut -> true
    }

  /**
   * The action button label, or `null` when [hasAction] is false.
   */
  val actionTitle: String?
    get() = when (this) {
      is Active -> null
      is Expiring -> "Refresh"
      is ActiveElsewhere, is SignedOut -> "Sign in again"
    }

  /**
   * Semantic colour role for the banner, expressed as a string token so that
   * Compose / XML / test code can map it to the actual colour resource without
   * coupling the SDK to any UI framework.
   *
   * Expected values: "positive" | "warning" | "information" | "removed"
   */
  val colorRole: String
    get() = when (this) {
      is Active -> "positive"
      is Expiring -> "warning"
      is ActiveElsewhere -> "information"
      is SignedOut -> "removed"
    }
}

/**
 * Pure-logic handler for session banner actions.
 *
 * In a real app this would coordinate with an auth token repository.
 * Here it returns the next [SessionState] so the calling ViewModel can update
 * its state holder without the banner knowing about coroutines.
 *
 * The payment context (amount, recipient, reference) is intentionally untouched
 * by this function – the UI layer must not reset form fields on a session event.
 *
 * @param current The current session state when the user tapped the action button.
 * @return The next session state to display. Returns [current] unchanged for
 *         states that have no action.
 */
fun handleSessionAction(current: SessionState): SessionState = when (current) {
  is SessionState.Expiring -> SessionState.Active  // optimistic: token refresh succeeded
  is SessionState.ActiveElsewhere, is SessionState.SignedOut -> SessionState.Active  // re-auth succeeded
  is SessionState.Active -> SessionState.Active    // no-op: active state has no action
}
