# Meridian mobile browser companion

A phone-first React/TypeScript client of the real Java rehearsal API. This is explicitly not the Swift/Android binary; those live in the sibling `ios/` and `android/` folders.

```sh
npm ci
npm run dev
```

Runs at port5176, proxying `/api/v1` and `/api/v2` to `MERIDIAN_API_TARGET` (default http://localhost:8080). Start the Java API first, or use the one-command launcher in `meridian-api` to run all three together. Payment status is read with `GET /api/v2/payment-intents/{id}`. A stored intent snapshot resumes that lookup after a refresh. Declined payments are not submitted again automatically.

The app displays server state only. It polls every two seconds, guards mutations against stale polls, retains the payment key after a lost response, and lets you switch shared rooms. Payment, history, budget edits and reset use the API. Provider selection intentionally remains two hardcoded entries. GBP amounts are integer pence.

Run `npm run check` for lint/build/unit checks. The full cross-client browser test is in `meridian-web/tests/connected`; it must run with API and both clients up. See the API repo's connected rehearsal guide.
