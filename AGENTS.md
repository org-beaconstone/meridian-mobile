# Meridian Mobile

- Deliver actual Swift and Kotlin client code plus native UI source, not a relabeled web-only app.
- If a browser companion is included for rehearsal, label it explicitly. Never claim device builds passed unless tested.
- Connect to the same Java backend API and X-Rehearsal-Session as meridian-web.
- GBP integer pence only. Provider baseline hardcodes Adyen card and Worldpay bank; no third provider named or implemented.
- No real payments, credentials or provider network calls. Don't send to a different provider on timeout.
- Preserve user-selected session across requests, check HTTP errors, and retain idempotency IDs for uncertain retries.
- Never commit generated builds, credentials or personal local SDK paths.
