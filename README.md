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

Verified on macOS: Swift SDK, actual SwiftUI desktop executable compilation, and real Java transport including payment, duplicate-key retry, pending response and reset. `MeridianSDKChecks` now runs 27 assertions; Swift 6.0.3 on Linux ran that executable. The desktop UI uses the same Swift source intended for iOS. Native desktop interactions were not UI-automated, and the SwiftUI desktop target was not rebuilt in this Linux environment.

For an iOS project, install Xcode and XcodeGen, then `cd ios && xcodegen generate`. `project.yml` builds `App/MeridianApp.swift` with the local SDK package. No iOS simulator/device build was run on the authoring machine because full Xcode was unavailable. Local network HTTP is for the rehearsal only; use HTTPS for any shared hosted endpoint.

## Kotlin SDK and Android Compose

```sh
cd android
mvn clean verify
# With Android Studio / SDK API34 and Gradle8.2.1:
gradle :app:assembleDebug
```

`android/sdk` is the single Kotlin source tree, used by both Maven and Gradle build definitions. Maven compilation was verified; the Android Gradle build was not run locally. Maven executes 26 tests, including a local HTTP transport check for session and idempotency headers, HTTP 202 pending behavior, and `POST /api/v2/payment-intents`. `LiveChecksKt` also passed against the real Spring Boot API (bank payment, duplicate key, pending and reset) before payment intents were added; that live check still uses `/api/v1` because the published Java API does not expose v2. `android/app` contains the native Compose customer UI. No APK or Android device build was verified locally because Android SDK was unavailable.

Android emulator base URL: `http://10.0.2.2:8080/api/v1`. iOS simulator/macOS: `http://127.0.0.1:8080/api/v1`. Configure the same room as the web client. Release Android manifest disallows cleartext; debug enables it for local rehearsal.

## Deliberate baseline

Payment methods are hardcoded to Adyen/card and Worldpay/bank in native UI. This preserves the documented mobile configuration gap rather than quietly implementing the future provider change. No real provider calls, account credentials, SCA, or production authentication exist here. A room ID is a synthetic-data partition, not a security boundary.

## Payment intent confirmation

The review screen locks a GBP quote (amount, rehearsal fee, Adyen or Worldpay rail, expiry, consent) and submits that canonical JSON once to `POST /api/v2/payment-intents`. Each attempt gets a new idempotency key and SHA-256 payload hash. Rapid taps and terminal responses — succeeded, declined, or action required — do not create another intent. An uncertain HTTP failure keeps the same key, hash, method, and bank. The published Java contract is still `/api/v1`; a missing v2 route is shown as an HTTP error and the same intent can be retried. The browser companion is labelled as a rehearsal preview, not a native binary.

See [source context](https://github.com/org-beaconstone/meridian-api/blob/main/docs/context.md), [API contract](https://github.com/org-beaconstone/meridian-api/blob/main/docs/contract.md) and [connected runbook](https://github.com/org-beaconstone/meridian-api/blob/main/docs/connected-rehearsal.md). Existing Kaizen site remains standalone; no Java hosting is implied.
