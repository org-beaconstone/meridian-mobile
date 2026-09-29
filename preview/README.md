# Meridian mobile browser companion

A phone-first React/TypeScript client of the real Java rehearsal API. This is explicitly not the Swift/Android binary; those live in the sibling `ios/` and `android/` folders.

```sh
npm ci
npm run dev
```

Runs at port5176, proxying `/api/v1` to `MERIDIAN_API_TARGET` (default http://localhost:8080). Start the Java API first, or use the one-command launcher in `meridian-api` to run all three together.

The app displays server state only. It polls every two seconds, guards mutations against stale polls, retains the payment key after a lost response, and lets you switch shared rooms. Payment, history, budget edits and reset use the API. Provider selection intentionally remains two hardcoded entries. GBP amounts are integer pence.

When the API returns HTTP 202 `SCA_STEP_UP_REQUIRED`, this companion rehearses the same step-up state machine as the native apps and is labelled as a browser stand-in. It does not present Face ID, Touch ID, or BiometricPrompt. The in-app passcode `135790` is checked here and is not posted. A verified payment is sent again with `scaChallengeToken` and the original idempotency key.

Run `npm run check` for lint/build/unit checks. The full cross-client browser test is in `meridian-web/tests/connected`; it must run with API and both clients up. See the API repo's connected rehearsal guide.
