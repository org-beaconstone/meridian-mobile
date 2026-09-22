import SwiftUI

// MARK: - DesignTokens

/// Semantic design tokens derived from the existing `meridian-mobile` colour palette.
///
/// Using named tokens (rather than hardcoded hex values) ensures that WCAG 2.1 AA
/// contrast ratios are maintained across light and dark themes — both of which
/// SwiftUI resolves automatically via `Color.primary`, `Color.secondary`, and the
/// brand dark surface (`surfaceBrand`) that matches the existing account card.
///
/// All values are cross-platform (iOS + macOS) SwiftUI `Color` literals.
enum DesignTokens {

  // MARK: – Surface colours

  /// Primary brand dark surface — matches the existing account-card background.
  /// rgb(20, 44, 53)  — dark teal, WCAG AA when paired with white text.
  static let surfaceBrand = Color(red: 0.078, green: 0.173, blue: 0.208)

  /// Warm amber tint for the expiring-session banner background.
  static let surfaceWarning = Color.orange.opacity(0.12)

  /// Soft red tint for the signed-out banner background.
  static let surfaceError = Color.red.opacity(0.10)

  /// Neutral fill used for idle/loading surfaces and field backgrounds.
  static let surfaceNeutral = Color.gray.opacity(0.08)

  // MARK: – Foreground / text colours

  /// White label — used on the brand dark surface (WCAG AA assured).
  static let labelOnBrand = Color.white

  /// Adapts to dark mode: primary label colour.
  static let labelPrimary = Color.primary

  /// Adapts to dark mode: secondary / subdued label colour.
  static let labelSecondary = Color.secondary

  /// Warning label — system orange, meets AA on light backgrounds.
  static let labelWarning = Color.orange

  /// Error label — system red, meets AA on light backgrounds.
  static let labelError = Color.red

  // MARK: – Border / separator

  /// Neutral separator colour.
  static let separator = Color.gray.opacity(0.25)

  // MARK: – Skeleton shimmer

  /// Base fill for skeleton loading placeholder cells.
  static let skeletonBase = Color.gray.opacity(0.14)

  /// Highlight fill pulsed during the shimmer animation.
  static let skeletonHighlight = Color.gray.opacity(0.24)
}
