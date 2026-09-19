// swift-tools-version:6.0
import PackageDescription
let package = Package(
  name: "MeridianSDK", platforms: [.iOS(.v16), .macOS(.v13)],
  products: [.library(name: "MeridianSDK", targets: ["MeridianSDK"]), .executable(name: "MeridianSDKChecks", targets: ["MeridianSDKChecks"]), .executable(name: "MeridianDesktop", targets: ["MeridianDesktop"]), .executable(name: "MeridianLiveChecks", targets: ["MeridianLiveChecks"])],
  targets: [
    .target(name: "MeridianSDK", path: "MeridianSDK/Sources/MeridianSDK"),
    .executableTarget(name: "MeridianSDKChecks", dependencies: ["MeridianSDK"], path: "Tests/MeridianSDKChecks"),
    .executableTarget(name: "MeridianDesktop", dependencies: ["MeridianSDK"], path: "App"),
    .executableTarget(name: "MeridianLiveChecks", dependencies: ["MeridianSDK"], path: "LiveChecks")
  ], swiftLanguageModes: [.v5]
)
