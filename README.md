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

Verified on macOS: Swift SDK, actual SwiftUI desktop executable compilation, the original SDK assertions, and real Java transport including payment, duplicate-key retry, pending response and reset. The check executable now also covers gateway retry and corridor-health polling. The desktop UI uses the same Swift source intended for iOS. Native desktop interactions were not UI-automated.

For an iOS project, install Xcode and XcodeGen, then `cd ios && xcodegen generate`. `project.yml` builds `App/MeridianApp.swift` with the local SDK package. No iOS simulator/device build was run on the authoring machine because full Xcode was unavailable. Local network HTTP is for the rehearsal only; use HTTPS for any shared hosted endpoint.

## Kotlin SDK and Android Compose

```sh
cd android
mvn clean verify
# With Android Studio / SDK API34 and Gradle8.2.1:
gradle :app:assembleDebug
```

`android/sdk` is the single Kotlin source tree, used by both Maven and Gradle build definitions. Maven compilation was verified; the Android Gradle build was not run locally. Maven executes the SDK tests, including local HTTP transport checks for session and idempotency headers, HTTP 202 pending behavior, HTTP 502/504 retry with the same payment key, and `/session/health` polling. `LiveChecksKt` also passed against the real Spring Boot API (bank payment, duplicate key, pending and reset). `android/app` contains the native Compose customer UI. No APK or Android device build was verified locally because Android SDK was unavailable.

Android emulator base URL: `http://10.0.2.2:8080/api/v1`. iOS simulator/macOS: `http://127.0.0.1:8080/api/v1`. Configure the same room as the web client. Release Android manifest disallows cleartext; debug enables it for local rehearsal.

## Network resilience

Payment submission retries HTTP 502 and 504 with exponential backoff (200ms, 400ms, then capped at 1600ms, plus jitter) for at most 3 attempts. Every attempt keeps the same `Idempotency-Key`, rehearsal room, amount, and rail. Simulated business responses, including HTTP 503, are not retried and are not sent to the other provider. When the attempts are exhausted, the native screens and the browser companion show an inline retry banner. Amount, recipient, reference, and the last ledger snapshot stay in place across those retries and across a dropped poll.

The SDKs also poll `GET /api/v1/session/health` about every 5 seconds with `X-Rehearsal-Session`. A missing endpoint is ignored. A GBP corridor marks a rail degraded or in outage only for the hardcoded pairing: Adyen card and Worldpay bank. The UI then offers the other healthy rail. Accepting that offer only changes the selected method; it does not submit a payment.

Session health shape:

```json
{"status":"DEGRADED","simulation":true,"corridors":[{"id":"GB","currency":"GBP","status":"degraded","rails":[{"method":"card","provider":"adyen","status":"outage"},{"method":"bank","provider":"worldpay","status":"healthy"}]}]}
```

## Deliberate baseline

Payment methods are hardcoded to Adyen/card and Worldpay/bank in native UI. This preserves the documented mobile configuration gap rather than quietly implementing the future provider change. No real provider calls, account credentials, SCA, or production authentication exist here. A room ID is a synthetic-data partition, not a security boundary.

See [source context](https://github.com/org-beaconstone/meridian-api/blob/main/docs/context.md), [API contract](https://github.com/org-beaconstone/meridian-api/blob/main/docs/contract.md) and [connected runbook](https://github.com/org-beaconstone/meridian-api/blob/main/docs/connected-rehearsal.md). Existing Kaizen site remains standalone; no Java hosting is implied.
