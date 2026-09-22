package com.atlassian.meridian.ui

/**
 * Client-side feature flags for the Meridian native Android app.
 *
 * The revamped authentication session banner and the net-new onboarding /
 * payment UI components ship behind the *same* client-side flag as the dynamic
 * catalog work, so the whole surface can be dogfooded internally before it is
 * turned on for everyone. The flag is OFF by default: production builds keep
 * the existing screen until the flag is deliberately enabled.
 *
 * This is intentionally a simple in-process flag (no remote config, no
 * network) so it never blocks or delays the primary sign-in action and never
 * performs a provider network call.
 */
object FeatureFlags {
  /**
   * Master flag for the revamped authentication experience: session banner,
   * onboarding carousel + page indicator, grouped card fields, and the
   * provider loading skeleton / inline retry pattern.
   *
   * Off by default. For internal dogfooding this can be overridden at runtime
   * via [override] (e.g. from a debug menu) without shipping a new default.
   */
  const val REVAMPED_AUTH_UI_DEFAULT = false

  @Volatile
  private var override: Boolean? = null

  /** Resolve the effective flag value, honouring any runtime override. */
  val revampedAuthUiEnabled: Boolean
    get() = override ?: REVAMPED_AUTH_UI_DEFAULT

  /** Runtime override for internal dogfooding. Pass null to clear. */
  fun override(enabled: Boolean?) {
    override = enabled
  }
}
