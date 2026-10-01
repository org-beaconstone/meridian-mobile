// swift-tools-version:6.0
import PackageDescription
let package = Package(
  name: "MeridianSDK", platforms: [.iOS(.v16), .macOS(.v13)],
  products: [
    .library(name: "MeridianSDK", targets: ["MeridianSDK"]),
    .executable(name: "MeridianSDKChecks",    targets: ["MeridianSDKChecks"]),
    .executable(name: "MeridianDesktop",      targets: ["MeridianDesktop"]),
    .executable(name: "MeridianLiveChecks",   targets: ["MeridianLiveChecks"]),
    .executable(name: "MeridianContractChecks", targets: ["MeridianContractChecks"]),
    .executable(name: "MeridianScenarioChecks", targets: ["MeridianScenarioChecks"]),
    .executable(name: "MeridianSecurityChecks", targets: ["MeridianSecurityChecks"]),
    .executable(name: "MeridianA11yChecks",     targets: ["MeridianA11yChecks"]),
  ],
  targets: [
    .target(name: "MeridianSDK", path: "MeridianSDK/Sources/MeridianSDK"),
    .executableTarget(name: "MeridianSDKChecks",      dependencies: ["MeridianSDK"], path: "Tests/MeridianSDKChecks"),
    .executableTarget(name: "MeridianDesktop",        dependencies: ["MeridianSDK"], path: "App"),
    .executableTarget(name: "MeridianLiveChecks",     dependencies: ["MeridianSDK"], path: "LiveChecks"),
    .executableTarget(name: "MeridianContractChecks", dependencies: ["MeridianSDK"], path: "Tests/ContractChecks"),
    .executableTarget(name: "MeridianScenarioChecks", dependencies: ["MeridianSDK"], path: "Tests/ScenarioChecks"),
    .executableTarget(name: "MeridianSecurityChecks", dependencies: ["MeridianSDK"], path: "Tests/SecurityChecks"),
    .executableTarget(name: "MeridianA11yChecks",     dependencies: ["MeridianSDK"], path: "Tests/A11yChecks"),
  ], swiftLanguageModes: [.v5]
)
