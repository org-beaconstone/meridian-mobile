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

Verified on macOS: Swift SDK, actual SwiftUI desktop executable compilation, and real Java transport including payment, duplicate-key retry, pending response and reset. The desktop UI uses the same Swift source intended for iOS. Native desktop interactions were not UI-automated. The executable SDK checks now include tracing and redaction; 23 checks passed on Linux with Swift 6.0.3. The SwiftUI desktop target was not rebuilt in that run.

For an iOS project, install Xcode and XcodeGen, then `cd ios && xcodegen generate`. `project.yml` builds `App/MeridianApp.swift` with the local SDK package. No iOS simulator/device build was run on the authoring machine because full Xcode was unavailable. Local network HTTP is for the rehearsal only; use HTTPS for any shared hosted endpoint.

## Kotlin SDK and Android Compose

```sh
cd android
mvn clean verify
# With Android Studio / SDK API34 and Gradle8.2.1:
gradle :app:assembleDebug
```

`android/sdk` is the single Kotlin source tree, used by both Maven and Gradle build definitions. Maven compilation was verified; the Android Gradle build was not run locally. Maven executes 25 tests, including an actual local HTTP transport check for session, idempotency, and `traceparent` headers, HTTP 202 pending behavior, span timers, and redacted corridor telemetry. `LiveChecksKt` also passed against the real Spring Boot API (bank payment, duplicate key, pending and reset) before tracing was added; that live pass was not repeated here. `android/app` contains the native Compose customer UI. No APK or Android device build was verified locally because Android SDK was unavailable.

Android emulator base URL: `http://10.0.2.2:8080/api/v1`. iOS simulator/macOS: `http://127.0.0.1:8080/api/v1`. Configure the same room as the web client. Release Android manifest disallows cleartext; debug enables it for local rehearsal.

## Tracing and sanitized telemetry

The Swift and Kotlin SDKs inject a W3C `traceparent` header (`00-{traceId}-{spanId}-01`) on outgoing HTTP calls, including `/catalog`, `/payments`, and `/session/health`. Client spans record duration for dynamic catalog parsing (`catalog.parse`), local biometric prompt resolution (`biometric.prompt`), and the payment gateway roundtrip (`payment.gateway`). Error events keep the error code and failure stage. Primary account numbers that pass the Luhn check, and IBANs that pass the mod-97 check, are redacted before they are stored in the in-memory log or shown from a gateway error string. The payment note is still sent to the API and is not copied into telemetry.

Session health polls `GET /session/health` on a 15 second interval. Connection changes are recorded once per change. A corridor moving to `degraded` or `down` emits one telemetry event. An unavailable local biometric sensor records `SCA_FALLBACK` and does not switch the selected Adyen card or Worldpay bank method. Traces stay in process; there is no collector export and no provider network call.

The browser companion under `preview/` mirrors the same header, span names, and redaction for rehearsal. It is not a native build. Android and iOS device builds were not run for this change.

## Deliberate baseline

Payment methods are hardcoded to Adyen/card and Worldpay/bank in native UI. This preserves the documented mobile configuration gap rather than quietly implementing the future provider change. No real provider calls, account credentials, SCA, or production authentication exist here. A room ID is a synthetic-data partition, not a security boundary.

See [source context](https://github.com/org-beaconstone/meridian-api/blob/main/docs/context.md), [API contract](https://github.com/org-beaconstone/meridian-api/blob/main/docs/contract.md) and [connected runbook](https://github.com/org-beaconstone/meridian-api/blob/main/docs/connected-rehearsal.md). Existing Kaizen site remains standalone; no Java hosting is implied.
