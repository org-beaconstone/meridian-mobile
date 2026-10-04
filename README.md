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

Verified on macOS: Swift SDK, actual SwiftUI desktop executable compilation, the original 20 SDK assertions, and real Java transport including payment, duplicate-key retry, pending response and reset. The check executable now contains 36 assertions, including the canary gate. The desktop UI uses the same Swift source intended for iOS. Native desktop interactions were not UI-automated.

For an iOS project, install Xcode and XcodeGen, then `cd ios && xcodegen generate`. `project.yml` builds `App/MeridianApp.swift` with the local SDK package. No iOS simulator/device build was run on the authoring machine because full Xcode was unavailable. Local network HTTP is for the rehearsal only; use HTTPS for any shared hosted endpoint.

## Kotlin SDK and Android Compose

```sh
cd android
mvn clean verify
# With Android Studio / SDK API34 and Gradle8.2.1:
gradle :app:assembleDebug
```

`android/sdk` is the single Kotlin source tree, used by both Maven and Gradle build definitions. Maven compilation was verified; the Android Gradle build was not run locally. The Maven suite includes the original transport checks plus the canary gate, including an actual local HTTP transport check for session/idempotency headers and HTTP202 pending behavior. `LiveChecksKt` also passed against the real Spring Boot API (bank payment, duplicate key, pending and reset). `android/app` contains the native Compose customer UI. No APK or Android device build was verified locally because Android SDK was unavailable.

Android emulator base URL: `http://10.0.2.2:8080/api/v1`. iOS simulator/macOS: `http://127.0.0.1:8080/api/v1`. Configure the same room as the web client. Release Android manifest disallows cleartext; debug enables it for local rehearsal.

## Deliberate baseline

Payment methods are hardcoded to Adyen/card and Worldpay/bank in native UI. This preserves the documented mobile configuration gap rather than quietly implementing the future provider change. No real provider calls, account credentials, SCA, or production authentication exist here. A room ID is a synthetic-data partition, not a security boundary.

See [source context](https://github.com/org-beaconstone/meridian-api/blob/main/docs/context.md), [API contract](https://github.com/org-beaconstone/meridian-api/blob/main/docs/contract.md) and [connected runbook](https://github.com/org-beaconstone/meridian-api/blob/main/docs/connected-rehearsal.md). Existing Kaizen site remains standalone; no Java hosting is implied.

## Internal dogfood and canary rehearsal

Native Swift and Kotlin share a local rollout gate. It records an internal distribution manifest for the TestFlight internal track and the Google Play internal testing track, then walks a 14-day European pilot schedule of 5%, 25%, 50% and 100% across London-Dublin, Amsterdam-Frankfurt and Paris-Brussels. Promotion follows that schedule one step at a time, and only after staging and pilot rollback checks have passed. A phase advances when the sample has at least 100 payments, the error rate is within 1%, open incidents are zero, and settlement variance is 0 GBP pence. An open incident, a 1 pence settlement mismatch, or an error-rate breach rolls the canary population back to 0%. The internal dogfood audience stays eligible so testers can keep diagnosing. Open incidents are an operator-supplied count on the telemetry sample. Store upload stays with the operator; `uploadPerformed` remains false in this client. Cohort membership is a stable FNV-1a bucket of the rehearsal room and keeps the selected session and the Adyen card / Worldpay bank baseline. Rollback checks run in-process. They are a local procedure for the staging and pilot rings, and no device store build was uploaded.

`mvn -B clean verify` in `android` passed 38 tests, including the 16 canary cases. The 16 Swift rollout checks passed under Swift 6.0.3. The full Apple package build stays on the macOS workflow; this Linux pass compiled the rollout sources on their own because the existing client uses `URLSession`.
