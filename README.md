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

Verified on macOS: Swift SDK, actual SwiftUI desktop executable compilation, and real Java transport including payment, duplicate-key retry, pending response and reset. `swift run MeridianSDKChecks` runs 69 executable assertions, including W3C trace propagation, latency SLOs, the telemetry sanitizer, and PagerDuty threshold checks. That suite passed with Swift 6.0.3 on Linux. The desktop UI uses the same Swift source intended for iOS. Native desktop interactions were not UI-automated, and this Linux check did not rebuild the SwiftUI desktop target.

For an iOS project, install Xcode and XcodeGen, then `cd ios && xcodegen generate`. `project.yml` builds `App/MeridianApp.swift` with the local SDK package. No iOS simulator/device build was run on the authoring machine because full Xcode was unavailable. Local network HTTP is for the rehearsal only; use HTTPS for any shared hosted endpoint.

## Kotlin SDK and Android Compose

```sh
cd android
mvn clean verify
# With Android Studio / SDK API34 and Gradle8.2.1:
gradle :app:assembleDebug
```

`android/sdk` is the single Kotlin source tree, used by both Maven and Gradle build definitions. Maven compilation was verified; the Android Gradle build was not run locally. Maven executes 32 tests including an actual local HTTP transport check for session/idempotency headers, HTTP 202 pending behavior, W3C traceparent propagation, latency SLOs, and PagerDuty thresholds. `LiveChecksKt` also passed against the real Spring Boot API (bank payment, duplicate key, pending and reset). `android/app` contains the native Compose customer UI. No APK or Android device build was verified locally because Android SDK was unavailable.

Android emulator base URL: `http://10.0.2.2:8080/api/v1`. iOS simulator/macOS: `http://127.0.0.1:8080/api/v1`. Configure the same room as the web client. Release Android manifest disallows cleartext; debug enables it for local rehearsal.

## Client telemetry

Swift and Kotlin SDKs keep an OpenTelemetry-style trace for the rehearsal session. Every outbound call sends a W3C `traceparent` and `tracestate`, including `GET /catalog`, `GET /fx/quote`, `POST /payments`, and `GET /session/health`. Pass an upstream `traceparent` to keep that trace id, so the session span parents to the gateway span and each HTTP span parents to the client operation. `GET /fx/quote` asks for a GBP integer-pence quote only.

`payment.submit` spans are scored against a p95 under 1,200 ms. `biometric.prompt` spans are scored against under 300 ms. The prompt is a local rehearsal timer in the native payment screen, not a device biometric and not a real SCA ceremony. Confirming a payment records an SCA completion; editing the review records a drop-off.

Error logs and breadcrumbs run through a sanitizer that removes primary account numbers, labelled cardholder details, and IBAN strings. A local PagerDuty threshold check pages when the submission error rate exceeds 1.0% over 5 minutes, or when SCA drop-offs exceed 5%. The SDK does not call PagerDuty, Adyen, or Worldpay.

The browser companion in `preview/` is not the native SDK and does not emit these spans.

## Deliberate baseline

Payment methods are hardcoded to Adyen/card and Worldpay/bank in native UI. This preserves the documented mobile configuration gap rather than quietly implementing the future provider change. No real provider calls, account credentials, SCA, or production authentication exist here. A room ID is a synthetic-data partition, not a security boundary.

See [source context](https://github.com/org-beaconstone/meridian-api/blob/main/docs/context.md), [API contract](https://github.com/org-beaconstone/meridian-api/blob/main/docs/contract.md) and [connected runbook](https://github.com/org-beaconstone/meridian-api/blob/main/docs/connected-rehearsal.md). Existing Kaizen site remains standalone; no Java hosting is implied.
