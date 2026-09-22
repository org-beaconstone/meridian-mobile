import SwiftUI

// MARK: - OnboardingPage

/// Data model for a single page in the onboarding carousel.
struct OnboardingPage: Identifiable {
  let id: UUID
  let systemImageName: String
  let title: String
  let subtitle: String

  init(systemImageName: String, title: String, subtitle: String) {
    self.id = UUID()
    self.systemImageName = systemImageName
    self.title = title
    self.subtitle = subtitle
  }
}

// MARK: - OnboardingCarousel

/// Horizontal paging carousel that pairs an illustration, header, and subtitle
/// with a `PageIndicator` dot row beneath.
///
/// Built as a **net-new** component — no shared design-system carousel exists in
/// this repo. Uses `DesignTokens` for colour so light/dark themes meet WCAG 2.1 AA.
///
/// - On iOS the carousel uses native `.page` tab-view style for true swipe paging.
/// - On macOS (MeridianDesktop preview target) a lightweight fallback renderer is used
///   because `.tabViewStyle(.page(...))` is iOS-only.
@MainActor
struct OnboardingCarousel: View {
  let pages: [OnboardingPage]
  @State private var currentPage: Int = 0

  var body: some View {
    VStack(spacing: 16) {
      carouselBody
      PageIndicator(pageCount: pages.count, currentPage: currentPage)
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private var carouselBody: some View {
#if os(iOS)
    TabView(selection: $currentPage) {
      ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
        OnboardingPageView(page: page)
          .tag(index)
      }
    }
    .tabViewStyle(.page(indexDisplayMode: .never))
    .frame(height: 280)
    .animation(.easeInOut, value: currentPage)
#else
    // macOS fallback: simple VStack showing one page at a time with buttons
    if let page = pages[safe: currentPage] {
      OnboardingPageView(page: page)
        .frame(height: 280)
    }
    HStack {
      Button("‹") { if currentPage > 0 { currentPage -= 1 } }.disabled(currentPage == 0)
      Spacer()
      Button("›") { if currentPage < pages.count - 1 { currentPage += 1 } }.disabled(currentPage == pages.count - 1)
    }
    .padding(.horizontal, 32)
#endif
  }
}

// MARK: - OnboardingPageView

private struct OnboardingPageView: View {
  let page: OnboardingPage

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: page.systemImageName)
        .font(.system(size: 72))
        .foregroundStyle(DesignTokens.surfaceBrand)
        .accessibilityHidden(true)

      VStack(spacing: 8) {
        Text(page.title)
          .font(.title2)
          .fontWeight(.semibold)
          .multilineTextAlignment(.center)
          .foregroundStyle(DesignTokens.labelPrimary)

        Text(page.subtitle)
          .font(.body)
          .multilineTextAlignment(.center)
          .foregroundStyle(DesignTokens.labelSecondary)
          .padding(.horizontal, 24)
      }
    }
    .padding(.horizontal, 16)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(page.title). \(page.subtitle)")
  }
}

// MARK: - PageIndicator

/// Dot-based page indicator aligned beneath the `OnboardingCarousel`.
///
/// Built as a **net-new** component — no equivalent exists in this repo.
/// The active dot scales up slightly and uses the brand colour; inactive dots
/// are muted grey. VoiceOver announces the current page position.
@MainActor
struct PageIndicator: View {
  let pageCount: Int
  let currentPage: Int

  var body: some View {
    HStack(spacing: 8) {
      ForEach(0..<pageCount, id: \.self) { index in
        let isActive = index == currentPage
        Circle()
          .fill(isActive ? DesignTokens.surfaceBrand : DesignTokens.skeletonBase)
          .frame(
            width: isActive ? 10 : 7,
            height: isActive ? 10 : 7
          )
          .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Page \(currentPage + 1) of \(pageCount)")
    .accessibilityAddTraits(.updatesFrequently)
  }
}

// MARK: - Collection safe subscript helper

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
