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
swift test
swift run MeridianSDKChecks
swift run MeridianDesktop
# Against a running Java API:
MERIDIAN_TEST_API=http://127.0.0.1:8080/api/v1 swift test --filter testLiveContainerWhenConfigured
MERIDIAN_TEST_API=http://127.0.0.1:8080/api/v1 swift run MeridianLiveChecks
```

The executable SDK checks were previously verified on macOS, including SwiftUI desktop compilation. `swift test` is the XCTest rehearsal suite. On Linux it passed against an in-process contract double and, with `MERIDIAN_TEST_API` set, against the Spring Boot API. SwiftUI was not launched in that run. No iOS simulator or device run is claimed.

For an iOS project, install Xcode and XcodeGen, then `cd ios && xcodegen generate`. `project.yml` builds `App/MeridianApp.swift` with the local SDK package. No iOS simulator/device build was run on the authoring machine because full Xcode was unavailable. Local network HTTP is for the rehearsal only; use HTTPS for any shared hosted endpoint.

## Kotlin SDK and Android Compose

```sh
cd android
mvn clean verify
# With Android Studio / SDK API34 and Gradle8.2.1:
gradle :app:assembleDebug
```

`android/sdk` is the single Kotlin source tree, used by both Maven and Gradle build definitions. `mvn verify` runs the JUnit rehearsal suite on the JVM: catalogue hydration, GBP pence bounds from 0.01 to 10,000.00, settlement, idempotency, HTTP 202 pending confirmation, provider-unavailable retry, and transport failure. With `MERIDIAN_TEST_API` set, the same journey runs against the Spring Boot API. Robolectric, the Android Gradle build, and device builds were not run. `android/app` contains the native Compose customer UI.

Set `MERIDIAN_TEST_API` (for example `http://127.0.0.1:8080/api/v1`) to include the live container case in `mvn verify` and `swift test`. Amounts stay integer GBP pence. Card stays on Adyen and bank stays on Worldpay; a timeout retries the same idempotency key and method.

Android emulator base URL: `http://10.0.2.2:8080/api/v1`. iOS simulator/macOS: `http://127.0.0.1:8080/api/v1`. Configure the same room as the web client. Release Android manifest disallows cleartext; debug enables it for local rehearsal.

## Deliberate baseline

Payment methods are hardcoded to Adyen/card and Worldpay/bank in native UI. This preserves the documented mobile configuration gap rather than quietly implementing the future provider change. No real provider calls, account credentials, SCA, or production authentication exist here. A room ID is a synthetic-data partition, not a security boundary.

See [source context](https://github.com/org-beaconstone/meridian-api/blob/main/docs/context.md), [API contract](https://github.com/org-beaconstone/meridian-api/blob/main/docs/contract.md) and [connected runbook](https://github.com/org-beaconstone/meridian-api/blob/main/docs/connected-rehearsal.md). Existing Kaizen site remains standalone; no Java hosting is implied.
