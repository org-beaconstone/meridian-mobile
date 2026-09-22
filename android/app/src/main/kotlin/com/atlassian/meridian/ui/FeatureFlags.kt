package com.atlassian.meridian.ui

/**
 * Client-side feature flags for internal dogfooding.
 *
 * The revamped authentication session banner and the new native UI components (onboarding carousel,
 * page indicator, grouped expiry/CVV fields, loading skeleton and inline error/retry) ship behind
 * the SAME client-side flag as the dynamic catalog work so the whole authentication + dynamic
 * provider experience can be dogfooded internally as one unit.
 *
 * The flag is OFF by default. There is no shared remote-config/flagging library in meridian-mobile
 * today, so this is a simple in-process registry with an optional build-time/env override for
 * dogfood builds. It intentionally has no network dependency.
 */
object FeatureFlags {

  /**
   * Gates the dynamic provider catalog AND the revamped authentication UI (session banner + new
   * components). Off by default. Enable for internal dogfood builds only.
   *
   * Override precedence (first non-null wins), evaluated once at process start:
   *  1. JVM system property `meridian.dynamicAuthExperience`
   *  2. Environment variable `MERIDIAN_DYNAMIC_AUTH_EXPERIENCE`
   *  3. Default: false
   */
  val dynamicAuthExperience: Boolean by lazy {
    resolveBoolean(
      systemPropertyKey = "meridian.dynamicAuthExperience",
      envKey = "MERIDIAN_DYNAMIC_AUTH_EXPERIENCE",
      default = false,
    )
  }

  private fun resolveBoolean(
    systemPropertyKey: String,
    envKey: String,
    default: Boolean,
  ): Boolean {
    System.getProperty(systemPropertyKey)?.let { return it.toBooleanFlag(default) }
    System.getenv(envKey)?.let { return it.toBooleanFlag(default) }
    return default
  }

  private fun String.toBooleanFlag(default: Boolean): Boolean = when (trim().lowercase()) {
    "1", "true", "on", "yes", "enabled" -> true
    "0", "false", "off", "no", "disabled" -> false
    else -> default
  }
}
