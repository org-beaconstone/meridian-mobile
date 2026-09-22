import Foundation

// MARK: - FeatureFlags

/// Client-side feature flags for `meridian-mobile`.
///
/// All PAY-16 UI changes (authentication session banner, onboarding carousel,
/// page indicator, grouped card fields, provider loading skeleton/retry) are gated
/// behind `authSessionBannerEnabled`. The flag is **off by default** so the existing
/// UI is unchanged on production builds; toggle to `true` for internal dogfooding.
public struct FeatureFlags {
  private init() {}

  /// Enable the revamped authentication session banner and new UI components (PAY-16).
  ///
  /// Ships `false` by default. Set to `true` in debug/dogfooding builds.
  public static var authSessionBannerEnabled: Bool = false
}
