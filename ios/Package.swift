// swift-tools-version:6.0
import PackageDescription

var products: [Product] = [
  .library(name: "MeridianSDK", targets: ["MeridianSDK"]),
  .executable(name: "MeridianSDKChecks", targets: ["MeridianSDKChecks"]),
  .executable(name: "MeridianLiveChecks", targets: ["MeridianLiveChecks"]),
]
var targets: [Target] = [
  .target(name: "MeridianSDK", path: "MeridianSDK/Sources/MeridianSDK"),
  .executableTarget(name: "MeridianSDKChecks", dependencies: ["MeridianSDK"], path: "Tests/MeridianSDKChecks"),
  .testTarget(name: "MeridianRehearsalTests", dependencies: ["MeridianSDK"], path: "Tests/MeridianRehearsalTests"),
  .executableTarget(name: "MeridianLiveChecks", dependencies: ["MeridianSDK"], path: "LiveChecks"),
]
// SwiftUI source stays in App/ for Xcode and macOS. Linux package builds omit it.
#if os(macOS)
products.append(.executable(name: "MeridianDesktop", targets: ["MeridianDesktop"]))
targets.append(.executableTarget(name: "MeridianDesktop", dependencies: ["MeridianSDK"], path: "App"))
#endif

let package = Package(
  name: "MeridianSDK",
  platforms: [.iOS(.v16), .macOS(.v13)],
  products: products,
  targets: targets,
  swiftLanguageModes: [.v5]
)
