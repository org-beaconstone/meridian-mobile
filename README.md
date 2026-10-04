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

Verified on macOS: Swift SDK, actual SwiftUI desktop executable compilation, executable SDK assertions, and real Java transport including payment, duplicate-key retry, pending response and reset. The desktop UI uses the same Swift source intended for iOS. Native desktop interactions were not UI-automated. The SDK check executable also covers both catalog schemas, flag parsing, the room cache, and payment telemetry.

For an iOS project, install Xcode and XcodeGen, then `cd ios && xcodegen generate`. `project.yml` builds `App/MeridianApp.swift` with the local SDK package. No iOS simulator/device build was run on the authoring machine because full Xcode was unavailable. Local network HTTP is for the rehearsal only; use HTTPS for any shared hosted endpoint.

## Kotlin SDK and Android Compose

```sh
cd android
mvn clean verify
# With Android Studio / SDK API34 and Gradle8.2.1:
gradle :app:assembleDebug
```

`android/sdk` is the single Kotlin source tree, used by both Maven and Gradle build definitions. Maven compilation was verified; the Android Gradle build was not run locally. Maven executes the SDK tests, including an actual local HTTP transport check for session/idempotency headers, the feature-flag header, and HTTP202 pending behavior. `LiveChecksKt` also passed against the real Spring Boot API (bank payment, duplicate key, pending and reset). `android/app` contains the native Compose customer UI. No APK or Android device build was verified locally because Android SDK was unavailable.

Android emulator base URL: `http://10.0.2.2:8080/api/v1`. iOS simulator/macOS: `http://127.0.0.1:8080/api/v1`. Configure the same room as the web client. Release Android manifest disallows cleartext; debug enables it for local rehearsal.

## Feature flag

`enable_mobile_eu_payments` is read from `GET /api/v1/flags` on the Java API and cached per rehearsal room before the payment form renders. The Swift and Kotlin SDKs, the native screens, and the labelled browser companion all follow the same rule.

- Variant `legacy` (flag off, omitted, HTTP 404, or `killSwitch: true`): the payment form stays on the hardcoded Adyen card and Worldpay bank choices. Amounts stay GBP. Euro controls are not shown.
- Variant `dynamic` (flag on): payment methods hydrate from the catalog. The decoder accepts the legacy two-provider document and a dynamic `methods` document. Provider ids other than `adyen` and `worldpay` are dropped. GBP and EUR display controls are shown. Amounts remain integer minor units, and the shared ledger stays GBP pence.

Payment requests send `X-Meridian-Flag: enable_mobile_eu_payments=<variant>` and each SDK keeps a local telemetry record with that variant and the same idempotency key. A failed flag read uses the cached value for that room, then legacy. Turning the flag off on the server returns clients to the legacy form on the next refresh, without an app update.

```json
{ "enable_mobile_eu_payments": { "enabled": false, "variant": "legacy", "killSwitch": true } }
```

```json
{ "schema": "dynamic", "methods": [{ "providerId": "adyen", "method": "card", "name": "Adyen" }], "currencies": ["GBP", "EUR"] }
```

## Deliberate baseline

With the flag off, payment methods stay hardcoded to Adyen/card and Worldpay/bank. The dynamic catalog does not add another provider. No real provider calls, account credentials, SCA, or production authentication exist here. A room ID is a synthetic-data partition, not a security boundary.

See [source context](https://github.com/org-beaconstone/meridian-api/blob/main/docs/context.md), [API contract](https://github.com/org-beaconstone/meridian-api/blob/main/docs/contract.md) and [connected runbook](https://github.com/org-beaconstone/meridian-api/blob/main/docs/connected-rehearsal.md). Existing Kaizen site remains standalone; no Java hosting is implied.
