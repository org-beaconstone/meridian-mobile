// swift-tools-version:6.0
import PackageDescription
let package = Package(
  name: "MeridianSDK", platforms: [.iOS(.v16), .macOS(.v13)],
  products: [
    .library(name: "MeridianSDK", targets: ["MeridianSDK"]),
    .library(name: "MeridianUI", targets: ["MeridianUI"]),
    .executable(name: "MeridianSDKChecks", targets: ["MeridianSDKChecks"]),
    .executable(name: "MeridianDesktop", targets: ["MeridianDesktop"]),
    .executable(name: "MeridianLiveChecks", targets: ["MeridianLiveChecks"])
  ],
  targets: [
    .target(name: "MeridianSDK", path: "MeridianSDK/Sources/MeridianSDK"),
    .target(name: "MeridianUI", dependencies: ["MeridianSDK"], path: "MeridianUI"),
    .executableTarget(name: "MeridianSDKChecks", dependencies: ["MeridianSDK", "MeridianUI"], path: "Tests/MeridianSDKChecks"),
    .executableTarget(name: "MeridianDesktop", dependencies: ["MeridianSDK", "MeridianUI"], path: "App"),
    .executableTarget(name: "MeridianLiveChecks", dependencies: ["MeridianSDK"], path: "LiveChecks")
  ], swiftLanguageModes: [.v5]
)
