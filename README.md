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

An earlier macOS run verified the Swift package, the SwiftUI desktop executable, and the Java transport checks (payment, duplicate-key retry, pending response, and reset). The desktop UI uses the same Swift source intended for iOS. Native desktop interactions were not UI-automated. This SCA change was checked with Swift 6.0.3 on Linux: `swift run MeridianSDKChecks` passed 32 assertions. The SwiftUI desktop target and the iOS project were not rebuilt in that run, and universal-link association was not verified on a device.

For an iOS project, install Xcode and XcodeGen, then `cd ios && xcodegen generate`. `project.yml` builds `App/MeridianApp.swift` with the local SDK package. No iOS simulator/device build was run on the authoring machine because full Xcode was unavailable. Local network HTTP is for the rehearsal only; use HTTPS for any shared hosted endpoint.

## Kotlin SDK and Android Compose

```sh
cd android
mvn clean verify
# With Android Studio / SDK API34 and Gradle8.2.1:
gradle :app:assembleDebug
```

`android/sdk` is the single Kotlin source tree, used by both Maven and Gradle build definitions. Maven compilation was verified; the Android Gradle build was not run locally. Maven executes 34 tests including an actual local HTTP transport check for session/idempotency headers and HTTP202 pending behavior, plus signed bank-return checks. `LiveChecksKt` also passed against the real Spring Boot API (bank payment, duplicate key, pending and reset). `android/app` contains the native Compose customer UI, including the biometric prompt and the app-link intent filter. No APK or Android device build was verified locally because Android SDK was unavailable. App-link domain association was not verified on a device.

Android emulator base URL: `http://10.0.2.2:8080/api/v1`. iOS simulator/macOS: `http://127.0.0.1:8080/api/v1`. Configure the same room as the web client. Release Android manifest disallows cleartext; debug enables it for local rehearsal.

## Deliberate baseline

Payment methods are hardcoded to Adyen/card and Worldpay/bank in native UI. This preserves the documented mobile configuration gap rather than quietly implementing the future provider change. No real provider calls, account credentials, or production authentication exist here. A room ID is a synthetic-data partition, not a security boundary.

## Rehearsal SCA and bank handoff

Card payments ask for an on-device biometric, device PIN, or a 4–6 digit app PIN before `POST /payments`. The app PIN is compared in memory and discarded. Bank payments open only `https://bank.meridian-rehearsal.test/handoff` with one signed `state` parameter. iOS listens for the universal link and Android for the app link on `https://app.meridian-rehearsal.test/bank/return`. The return token is an HMAC-SHA256 over a canonical payload, with a 5-minute expiry and a one-time nonce. Replayed, invalid, expired, or mismatched returns do not submit a payment and do not replace the idempotency key. The signing key is random process memory, not a provider secret. The `.test` host is reserved and is not Adyen or Worldpay. The browser companion does not implement this native step.

See [source context](https://github.com/org-beaconstone/meridian-api/blob/main/docs/context.md), [API contract](https://github.com/org-beaconstone/meridian-api/blob/main/docs/contract.md) and [connected runbook](https://github.com/org-beaconstone/meridian-api/blob/main/docs/connected-rehearsal.md). Existing Kaizen site remains standalone; no Java hosting is implied.
