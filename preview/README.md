# Meridian mobile browser companion

A phone-first React/TypeScript client of the real Java rehearsal API. This is explicitly not the Swift/Android binary; those live in the sibling `ios/` and `android/` folders.

```sh
npm ci
npm run dev
```

Runs at port5176, proxying `/api/v1` to `MERIDIAN_API_TARGET` (default http://localhost:8080). Start the Java API first, or use the one-command launcher in `meridian-api` to run all three together.

The app displays server state only. It polls ledger state every two seconds and `GET /api/v1/session/health` every five seconds, guards mutations against stale polls, retries HTTP 502 and 504 with the same payment key, and lets you switch shared rooms. A degraded Adyen card or Worldpay bank rail can be switched only by an explicit choice. Payment, history, budget edits and reset use the API. Provider selection intentionally remains two hardcoded entries. GBP amounts are integer pence. This browser companion is not the native Swift or Kotlin client.

Run `npm run check` for lint/build/unit checks. The full cross-client browser test is in `meridian-web/tests/connected`; it must run with API and both clients up. See the API repo's connected rehearsal guide.
