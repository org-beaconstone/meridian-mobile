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

Verified on macOS: Swift SDK, actual SwiftUI desktop executable compilation, and real Java transport including payment, duplicate-key retry, pending response and reset. The desktop UI uses the same Swift source intended for iOS. Native desktop interactions were not UI-automated. On Linux Swift 6.0.3, `swift run MeridianSDKChecks` passed 31/31, including the PSD2 step-up handler. The SwiftUI desktop target was not built on Linux because SwiftUI is unavailable there. Face ID and Touch ID were not exercised on a device.

For an iOS project, install Xcode and XcodeGen, then `cd ios && xcodegen generate`. `project.yml` builds `App/MeridianApp.swift` with the local SDK package. No iOS simulator/device build was run on the authoring machine because full Xcode was unavailable. Local network HTTP is for the rehearsal only; use HTTPS for any shared hosted endpoint.

## Kotlin SDK and Android Compose

```sh
cd android
mvn clean verify
# With Android Studio / SDK API34 and Gradle8.2.1:
gradle :app:assembleDebug
```

`android/sdk` is the single Kotlin source tree, used by both Maven and Gradle build definitions. `mvn -B clean verify` passed 29 tests, including a local HTTP transport check for session and idempotency headers, HTTP 202 pending behavior, and HTTP 202 `SCA_STEP_UP_REQUIRED` resubmit with the original idempotency key. The Android Gradle build was not run. `android/app` contains the native Compose customer UI and the `BiometricPrompt` step-up. No APK or Android device build was verified because the Android SDK was unavailable, so BiometricPrompt itself was not launched on hardware.

Android emulator base URL: `http://10.0.2.2:8080/api/v1`. iOS simulator/macOS: `http://127.0.0.1:8080/api/v1`. Configure the same room as the web client. Release Android manifest disallows cleartext; debug enables it for local rehearsal.

## Deliberate baseline

Payment methods are hardcoded to Adyen/card and Worldpay/bank in native UI. This preserves the documented mobile configuration gap rather than quietly implementing the future provider change. No real provider calls, account credentials, or production authentication exist here. A room ID is a synthetic-data partition, not a security boundary.

PSD2 step-up is a local rehearsal handler. When the Java API returns HTTP 202 with `SCA_STEP_UP_REQUIRED`, iOS presents LocalAuthentication and Android presents BiometricPrompt with the prompt “Confirm with Face ID / Fingerprint to authorize European payment”. If biometrics fail or are unavailable, the same payment stays on screen and an in-app passcode is checked on device. The rehearsal passcode is `135790`. It is not sent to the API. After verification the original payment is posted again with `scaChallengeToken` and the same `Idempotency-Key` and `X-Rehearsal-Session`. Amounts stay integer GBP pence. The browser companion can rehearse the same state machine and is labelled as such; it does not perform device biometrics. The current Java API rejects unknown payment fields, so a live rehearsal room will not emit this step-up until the API accepts `scaChallengeToken`.

See [source context](https://github.com/org-beaconstone/meridian-api/blob/main/docs/context.md), [API contract](https://github.com/org-beaconstone/meridian-api/blob/main/docs/contract.md) and [connected runbook](https://github.com/org-beaconstone/meridian-api/blob/main/docs/connected-rehearsal.md). Existing Kaizen site remains standalone; no Java hosting is implied.
