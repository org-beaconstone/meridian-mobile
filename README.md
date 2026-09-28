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

`swift run MeridianSDKChecks` is 27 assertions, including the HTTP 202 SCA resubmit, and passed on Swift 6.2. The SwiftUI desktop executable uses the same Swift source intended for iOS and was not rebuilt here. Face ID and Touch ID use LocalAuthentication; a missing sensor falls back to the in-app passcode. No iOS simulator or device biometric run was performed.

For an iOS project, install Xcode and XcodeGen, then `cd ios && xcodegen generate`. `project.yml` builds `App/MeridianApp.swift` with the local SDK package. No iOS simulator/device build was run on the authoring machine because full Xcode was unavailable. Local network HTTP is for the rehearsal only; use HTTPS for any shared hosted endpoint.

## Kotlin SDK and Android Compose

```sh
cd android
mvn clean verify
# With Android Studio / SDK API34 and Gradle8.2.1:
gradle :app:assembleDebug
```

`android/sdk` is the single Kotlin source tree, used by both Maven and Gradle build definitions. `mvn clean verify` passed 29 tests, including local HTTP checks for session and idempotency headers, HTTP 202 pending, and the SCA step-up resubmit. The Android Gradle app was not assembled. `android/app` contains the native Compose customer UI and BiometricPrompt. No APK or Android device build was verified because the Android SDK was unavailable. `LiveChecksKt` still targets the real Spring Boot API and was not re-run against it here.

Android emulator base URL: `http://10.0.2.2:8080/api/v1`. iOS simulator/macOS: `http://127.0.0.1:8080/api/v1`. Configure the same room as the web client. Release Android manifest disallows cleartext; debug enables it for local rehearsal.

## Deliberate baseline

Payment methods are hardcoded to Adyen/card and Worldpay/bank in native UI. This preserves the documented mobile configuration gap rather than quietly implementing the future provider change. No real provider calls or production authentication exist here. A room ID is a synthetic-data partition, not a security boundary.

PSD2 step-up is a local rehearsal handler. When `POST /payments` returns HTTP 202 with `code: SCA_STEP_UP_REQUIRED`, the client extracts `challenge.payload` and `challenge.expiresAt` (top-level `challengePayload`, `expiresAt`, `expirationTimestamp`, or `expiration` are also accepted). Face ID / Touch ID (`LocalAuthentication`) or Android `BiometricPrompt` shows “Confirm with Face ID / Fingerprint to authorize European payment”. If that check fails or the sensor is unavailable, the in-app 6-digit passcode is used and the recipient, GBP pence amount, and idempotency key stay put. After verification the same payment is posted again with `scaChallengeToken` and the original `Idempotency-Key`. The passcode and biometric sample are not sent. A timeout does not switch the Adyen card or Worldpay bank method. An expired or failed challenge shows “Authentication challenge failed. Please verify with your passcode.” The browser companion rehearses the same contract and is not the native biometric prompt.

See [source context](https://github.com/org-beaconstone/meridian-api/blob/main/docs/context.md), [API contract](https://github.com/org-beaconstone/meridian-api/blob/main/docs/contract.md) and [connected runbook](https://github.com/org-beaconstone/meridian-api/blob/main/docs/connected-rehearsal.md). Existing Kaizen site remains standalone; no Java hosting is implied.
