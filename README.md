# Meridian Mobile

Native **Swift and Kotlin** payment clients, plus a clearly labelled browser companion for the connected rehearsal. They use [meridian-api](https://github.com/org-beaconstone/meridian-api) and share state with [meridian-web](https://github.com/org-beaconstone/meridian-web) using `X-Rehearsal-Session`.

## Run the whole rehearsal

Check out all three repos as siblings. From `meridian-api`, run:

```sh
node scripts/rehearsal.mjs
```

Web opens at port 5175, mobile browser companion at 5176, Java API at 8080. All use room `meridian-rehearsal`. Configurable ports and Docker Compose are documented in the API repo. The browser companion is **not a native binary**.

## Swift SDK and native SwiftUI

```sh
cd ios
swift build
swift run MeridianSDKChecks
swift run MeridianDesktop
# Against a running Java API:
MERIDIAN_TEST_API=http://127.0.0.1:8080/api/v1 swift run MeridianLiveChecks
```

Verified on macOS: Swift SDK, actual SwiftUI desktop executable compilation, 20 executable SDK assertions, and real Java transport including payment, duplicate-key retry, pending response and reset. The desktop UI uses the same Swift source intended for iOS. Native desktop interactions were not UI-automated.

For an iOS project, install Xcode and XcodeGen, then `cd ios && xcodegen generate`. `project.yml` builds `App/MeridianApp.swift` with the local SDK package. No iOS simulator/device build was run on the authoring machine because full Xcode was unavailable. Local network HTTP is for the rehearsal only; use HTTPS for any shared hosted endpoint.

## Kotlin SDK and Android Compose

```sh
cd android
mvn clean verify
# With Android Studio / SDK API34 and Gradle8.2.1:
gradle :app:assembleDebug
```

`android/sdk` is the single Kotlin source tree, used by both Maven and Gradle build definitions. Maven compilation was verified; the Android Gradle build was not run locally. Maven executes 22 tests including an actual local HTTP transport check for session/idempotency headers and HTTP202 pending behavior. `LiveChecksKt` also passed against the real Spring Boot API (bank payment, duplicate key, pending and reset). `android/app` contains the native Compose customer UI. No APK or Android device build was verified locally because Android SDK was unavailable.

Android emulator base URL: `http://10.0.2.2:8080/api/v1`. iOS simulator/macOS: `http://127.0.0.1:8080/api/v1`. Configure the same room as the web client. Release Android manifest disallows cleartext; debug enables it for local rehearsal.

## Property suites and mock container

Currency checks use integer GBP pence. The bounds exercised are £0.01 (1 pence) and £10,000.00 (1,000,000 pence), with half-up minor-unit rounding and MOD-97 IBAN checksums. SCA is simulated in process: biometric pass, biometric failure then passcode fallback, and timeout. A timeout keeps the original provider (Adyen for card, Worldpay for bank) and the same idempotency key. Packet-drop tests retry that same key and do not send the payment anywhere else.

```sh
cd ios && swift run MeridianPropertyChecks
cd android && mvn -B test
bash scripts/container-suite.sh
```

`scripts/container-suite.sh` packages `mock-container`, starts it, and runs the Kotlin journey. When `swift` is on `PATH` it also runs `MeridianContainerChecks`. Android instrumented coverage lives in `android/app/src/androidTest` and calls the same `JourneyRunner` against `http://10.0.2.2:8080/api/v1` (override with the `meridianApi` instrumentation argument).

Verified on this workspace: Kotlin Maven tests, including packet-drop retries; Swift property checks and the original SDK checks on Linux Swift 6.0.3; and both journey runners against the Spring Boot jar. The SwiftUI desktop executable was not rebuilt here. The Android instrumented test was not run on a device or emulator. Docker was not used to start the image.

The browser companion under `preview/` is not part of these native suites.

## Deliberate baseline

Payment methods are hardcoded to Adyen/card and Worldpay/bank in native UI. This preserves the documented mobile configuration gap rather than quietly implementing the future provider change. No real provider calls, account credentials, SCA, or production authentication exist here. A room ID is a synthetic-data partition, not a security boundary.

See [source context](https://github.com/org-beaconstone/meridian-api/blob/main/docs/context.md), [API contract](https://github.com/org-beaconstone/meridian-api/blob/main/docs/contract.md) and [connected runbook](https://github.com/org-beaconstone/meridian-api/blob/main/docs/connected-rehearsal.md). Existing Kaizen site remains standalone; no Java hosting is implied.
