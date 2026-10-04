// swift-tools-version:6.0
import PackageDescription
let package = Package(
  name: "MeridianSDK", platforms: [.iOS(.v16), .macOS(.v13)],
  products: [.library(name: "MeridianSDK", targets: ["MeridianSDK"]), .executable(name: "MeridianSDKChecks", targets: ["MeridianSDKChecks"]), .executable(name: "MeridianDesktop", targets: ["MeridianDesktop"]), .executable(name: "MeridianLiveChecks", targets: ["MeridianLiveChecks"]), .executable(name: "MeridianPropertyChecks", targets: ["MeridianPropertyChecks"]), .executable(name: "MeridianContainerChecks", targets: ["MeridianContainerChecks"])],
  targets: [
    .target(name: "MeridianSDK", path: "MeridianSDK/Sources/MeridianSDK"),
    .executableTarget(name: "MeridianSDKChecks", dependencies: ["MeridianSDK"], path: "Tests/MeridianSDKChecks"),
    .executableTarget(name: "MeridianDesktop", dependencies: ["MeridianSDK"], path: "App"),
    .executableTarget(name: "MeridianPropertyChecks", dependencies: ["MeridianSDK"], path: "Tests/PropertyChecks"),
    .executableTarget(name: "MeridianContainerChecks", dependencies: ["MeridianSDK"], path: "Tests/ContainerChecks"),
    .executableTarget(name: "MeridianLiveChecks", dependencies: ["MeridianSDK"], path: "LiveChecks")
  ], swiftLanguageModes: [.v5]
)
