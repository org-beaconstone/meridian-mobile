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

Previously verified on macOS: Swift SDK, SwiftUI desktop executable compilation, the original SDK assertions, and real Java transport including payment, duplicate-key retry, pending response and reset. The desktop UI uses the same Swift source intended for iOS. SDK checks now also cover the SCA step-up interceptor; those checks were not re-run on macOS for this change. Native desktop interactions and device biometric dialogs were not UI-automated. Face ID / Touch ID appears only when LocalAuthentication can evaluate biometrics; otherwise the SwiftUI confirmation uses the same sentence.

For an iOS project, install Xcode and XcodeGen, then `cd ios && xcodegen generate`. `project.yml` builds `App/MeridianApp.swift` with the local SDK package. No iOS simulator/device build was run on the authoring machine because full Xcode was unavailable. Local network HTTP is for the rehearsal only; use HTTPS for any shared hosted endpoint.

## Kotlin SDK and Android Compose

```sh
cd android
mvn clean verify
# With Android Studio / SDK API34 and Gradle8.2.1:
gradle :app:assembleDebug
```

`android/sdk` is the single Kotlin source tree, used by both Maven and Gradle build definitions. Maven compilation and 30 SDK tests were verified, including local HTTP checks for session and idempotency headers, HTTP 202 pending behavior, and the SCA step-up interceptor. The Android Gradle build was not run. `LiveChecksKt` previously passed against the real Spring Boot API (bank payment, duplicate key, pending and reset). `android/app` contains the native Compose customer UI and `BiometricPrompt`. No APK or Android device build was verified because the Android SDK was unavailable. When biometrics are not enrolled, the Compose screen shows a native confirmation with the same sentence.

Android emulator base URL: `http://10.0.2.2:8080/api/v1`. iOS simulator/macOS: `http://127.0.0.1:8080/api/v1`. Configure the same room as the web client. Release Android manifest disallows cleartext; debug enables it for local rehearsal.

## Deliberate baseline

Payment methods are hardcoded to Adyen/card and Worldpay/bank in native UI. This preserves the documented mobile configuration gap rather than quietly implementing the future provider change. No real provider calls, account credentials, or production authentication exist here. A room ID is a synthetic-data partition, not a security boundary.

European SCA is a local rehearsal step-up. When `POST /payments` returns HTTP 202 with `code: SCA_STEP_UP_REQUIRED`, `challengeToken`, and `challengeExpiresAt`, the native client shows Face ID / Touch ID or Android BiometricPrompt with “Confirm with Face ID / Fingerprint to authorize European payment”. A successful check resubmits the same body, the same `X-Rehearsal-Session`, and the original `Idempotency-Key`, plus header `X-Challenge-Verification`. That header is a local FNV-1a proof derived in under 300 ms. It is not a provider cryptogram. An expired step-up window does not resubmit; the UI asks the user to start the payment again with a new idempotency key. Uncertain network failures still keep the original key. The browser companion in `preview/` rehearses the same interceptor and is labelled as such; it is not the native biometric dialog. The current Java API does not emit this challenge.

See [source context](https://github.com/org-beaconstone/meridian-api/blob/main/docs/context.md), [API contract](https://github.com/org-beaconstone/meridian-api/blob/main/docs/contract.md) and [connected runbook](https://github.com/org-beaconstone/meridian-api/blob/main/docs/connected-rehearsal.md). Existing Kaizen site remains standalone; no Java hosting is implied.
