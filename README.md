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

Previously verified on macOS: Swift SDK, actual SwiftUI desktop executable compilation, and real Java transport including payment, duplicate-key retry, pending response and reset. `MeridianSDKChecks` now runs 36 assertions, including payment-intent snapshot resume, retention, account isolation, and a Keychain round trip. The desktop UI uses the same Swift source intended for iOS. Native desktop interactions were not UI-automated. Re-run the Swift checks on macOS to confirm the Keychain path in this environment.

For an iOS project, install Xcode and XcodeGen, then `cd ios && xcodegen generate`. `project.yml` builds `App/MeridianApp.swift` with the local SDK package. No iOS simulator/device build was run on the authoring machine because full Xcode was unavailable. Local network HTTP is for the rehearsal only; use HTTPS for any shared hosted endpoint.

## Kotlin SDK and Android Compose

```sh
cd android
mvn clean verify
# With Android Studio / SDK API34 and Gradle8.2.1:
gradle :app:assembleDebug
```

`android/sdk` is the single Kotlin source tree, used by both Maven and Gradle build definitions. Maven compilation was verified; the Android Gradle build was not run locally. Maven executes 36 tests including an actual local HTTP transport check for session/idempotency headers and HTTP202 pending behavior, plus payment-intent snapshot resume, retention, and account isolation. The Android `EncryptedSharedPreferences` store lives in `android/app` because it needs the Android Keystore and is not part of the JVM Maven module. `LiveChecksKt` also passed against the real Spring Boot API (bank payment, duplicate key, pending and reset). `android/app` contains the native Compose customer UI. No APK or Android device build was verified locally because Android SDK was unavailable.

Android emulator base URL: `http://10.0.2.2:8080/api/v1`. iOS simulator/macOS: `http://127.0.0.1:8080/api/v1`. Configure the same room as the web client. Release Android manifest disallows cleartext; debug enables it for local rehearsal.

## Payment intent snapshots

Native clients store a `PaymentIntentSnapshot` for each payment in platform protected storage: the iOS Keychain and Android `EncryptedSharedPreferences`. A record holds the payment intent id, idempotency key, business payload hash, status, and return-state hash, and it is scoped to the customer account. After a process restart the client loads any active intent and retries with the same idempotency key. Snapshots that have reached a terminal status are removed 24 hours later. The browser companion does not implement this store.

## Deliberate baseline

Payment methods are hardcoded to Adyen/card and Worldpay/bank in native UI. This preserves the documented mobile configuration gap rather than quietly implementing the future provider change. No real provider calls, account credentials, SCA, or production authentication exist here. A room ID is a synthetic-data partition, not a security boundary.

See [source context](https://github.com/org-beaconstone/meridian-api/blob/main/docs/context.md), [API contract](https://github.com/org-beaconstone/meridian-api/blob/main/docs/contract.md) and [connected runbook](https://github.com/org-beaconstone/meridian-api/blob/main/docs/connected-rehearsal.md). Existing Kaizen site remains standalone; no Java hosting is implied.
