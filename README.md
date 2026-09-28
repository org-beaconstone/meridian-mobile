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

The Swift check executable has 37 assertions: amount parsing, IBAN MOD-97, UUID v4 idempotency, the 60-second quote lock, and 502/504 retries that keep the same key and method. Those checks passed with Swift 6.0.3 on Linux. The SwiftUI desktop executable still targets macOS; it was not rebuilt in this environment, and no iOS simulator or device build was run. Earlier macOS verification covered the Java transport for payment, duplicate-key retry, pending response, and reset. The desktop UI uses the same Swift source intended for iOS.

For an iOS project, install Xcode and XcodeGen, then `cd ios && xcodegen generate`. `project.yml` builds `App/MeridianApp.swift` with the local SDK package. No iOS simulator/device build was run on the authoring machine because full Xcode was unavailable. Local network HTTP is for the rehearsal only; use HTTPS for any shared hosted endpoint.

## Kotlin SDK and Android Compose

```sh
cd android
mvn clean verify
# With Android Studio / SDK API34 and Gradle8.2.1:
gradle :app:assembleDebug
```

`android/sdk` is the single Kotlin source tree, used by both Maven and Gradle build definitions. Maven compilation was verified; the Android Gradle build was not run locally. Maven executes 31 tests, including a local HTTP transport check for session and idempotency headers, HTTP 202 pending behavior, FX quote parsing, and HTTP 502/504 retries that keep the same key and Worldpay bank method. `LiveChecksKt` was previously run against the real Spring Boot API (bank payment, duplicate key, pending and reset). `android/app` contains the native Compose customer UI. No APK or Android device build was verified locally because Android SDK was unavailable.

Android emulator base URL: `http://10.0.2.2:8080/api/v1`. iOS simulator/macOS: `http://127.0.0.1:8080/api/v1`. Configure the same room as the web client. Release Android manifest disallows cleartext; debug enables it for local rehearsal.

## Deliberate baseline

Payment methods are hardcoded to Adyen/card and Worldpay/bank in native UI. This preserves the documented mobile configuration gap rather than quietly implementing the future provider change. No real provider calls, account credentials, SCA, or production authentication exist here. A room ID is a synthetic-data partition, not a security boundary.

Each payment attempt uses one UUID v4 `Idempotency-Key`. HTTP 502 and 504 retry up to three times with exponential backoff (200ms, then 400ms) and that same key and method. A timeout does not switch between Adyen and Worldpay. EUR payments call `POST /api/v1/fx/quote`, show the locked recipient amount, and count down 60 seconds on the review screen. Confirmation stays disabled after expiry until the customer refreshes the rate. Bank transfers and EUR payments check the recipient IBAN with MOD-97 before anything is submitted. The debited amount stays integer GBP pence. The browser companion follows the same rules and is not a native build.

See [source context](https://github.com/org-beaconstone/meridian-api/blob/main/docs/context.md), [API contract](https://github.com/org-beaconstone/meridian-api/blob/main/docs/contract.md) and [connected runbook](https://github.com/org-beaconstone/meridian-api/blob/main/docs/connected-rehearsal.md). Existing Kaizen site remains standalone; no Java hosting is implied.
