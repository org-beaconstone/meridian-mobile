package com.atlassian.meridian.ui

/**
 * Presentation-layer model of the authentication session for the session banner.
 *
 * This is deliberately a UI concept, not an SDK/transport concept: the banner is a presentation
 * layer over existing session state and is independent of the catalog fetch. The values map to the
 * approved Figma concepts (signed out, expiring, re-authenticating) plus the neutral resolving state
 * and the positive active state.
 */
enum class SessionState {
  /** Session check has not yet resolved. Banner shows a neutral, non-alarming placeholder. */
  Checking,

  /** No valid session. User must sign in, but the primary sign-in action stays enabled. */
  SignedOut,

  /** Session is valid but close to expiry. Warn without blocking the user. */
  Expiring,

  /** A silent/interactive re-authentication is in progress. Informational, in-progress state. */
  Reauthenticating,

  /** Session is valid and active. */
  Active,
}

/**
 * Static copy for each banner state. Copy for active/expiring is finalized here from the Figma
 * concepts; kept in one place so it can be localized later.
 */
data class SessionBannerContent(
  val title: String,
  val detail: String,
) {
  companion object {
    fun forState(state: SessionState): SessionBannerContent = when (state) {
      SessionState.Checking -> SessionBannerContent(
        title = "Checking your session…",
        detail = "One moment while we confirm you're signed in.",
      )
      SessionState.SignedOut -> SessionBannerContent(
        title = "You're signed out",
        detail = "Sign in to see your account and make a payment.",
      )
      SessionState.Expiring -> SessionBannerContent(
        title = "Your session is about to expire",
        detail = "Sign in again to avoid interrupting your payment.",
      )
      SessionState.Reauthenticating -> SessionBannerContent(
        title = "Re-authenticating…",
        detail = "Reconnecting your session. You can keep going.",
      )
      SessionState.Active -> SessionBannerContent(
        title = "You're signed in",
        detail = "Your session is active.",
      )
    }
  }
}
