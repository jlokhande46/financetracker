# FinanceTracker — PWA

Web port of the iOS app. Exists because free Apple provisioning re-signs every
7 days, which kept breaking tracking continuity. An installed PWA never expires.

**Status: engine + backend scaffolded. UI not built yet.** The Swift app in
`../FinanceTracker` still runs and is unaffected by anything here.

## Why a backend at all

The Swift app captured SMS through an **App Intent** (`LogBankSMSIntent`) that
Shortcuts could run silently while the phone was locked. A PWA cannot expose an
App Intent — that's the one integration with no direct web equivalent.

The replacement keeps the automation, changes the transport:

```
Bank SMS  ->  Shortcuts automation  ->  POST /api/sms  ->  D1 inbox
                                                             |
                          PWA drains inbox -> parse -> classify -> IndexedDB
```

`Get Contents of URL` runs in background automations while locked, same as the
App Intent did — and unlike the App Intent it doesn't depend on an App Group
entitlement, which free-team signing strips anyway.

The second reason for a backend: **iOS PWAs cannot schedule local
notifications.** There is no Notification Triggers API in Safari. Every reminder
the Swift app fired via `UNCalendarNotificationTrigger` (bill due dates, the
daily tip) has to be pushed from a server cron instead. That's the `scheduled()`
handler in the Worker.

## Layout

```
web/
├── src/
│   ├── domain/          types + the 26 categories + 50/30/20 intent map
│   ├── parsing/         SMS parsers (8 bank formats) + tests
│   ├── categorization/  merchant normaliser + classifier cascade + tests
│   ├── ingest/          dedup -> parse -> normalise -> classify -> store
│   └── db/              Dexie (IndexedDB) schema + paged reads
└── worker/              Cloudflare Worker + D1 (Shortcut endpoint, Web Push)
```

## Two things fixed in the port

**Money is integer paise, not floating point.** Swift used `Decimal`; JS has no
decimal type and float arithmetic on currency is how you get `0.1 + 0.2` bugs in
a finance app. Everything is `Paise` (integer), converted to a display string
only at the edge. There's a test pinning this.

**Pagination is O(page), not O(everything).** The Swift feed re-filtered,
re-sorted and re-grouped the entire loaded set on each page, so page 5 was
reprocessing 500 rows. Here the IndexedDB `date` index does the ordering, so a
page costs the same whether it's the first or the twentieth.

## Tests

The Swift app had none — its parsing bugs (wrong amount, wrong direction on the
ICICI BookMyShow row) surfaced in production. Every real bank format is pinned
here.

```bash
npm test
```

## Local dev

```bash
npm install
npm run dev          # PWA
npx tsc --noEmit     # typecheck (includes the Worker)
```

## Deploying the backend

```bash
cd worker
npx wrangler d1 create financetracker      # put the id in wrangler.toml
npx wrangler d1 execute financetracker --file=schema.sql
npx wrangler secret put INGEST_TOKEN       # any long random string
npx wrangler deploy
```

Free tier covers a single-user app comfortably.

## Shortcut setup (replaces the App Intent)

1. Shortcuts → new automation → **Message Received**, from your bank sender IDs.
2. Action: **Get Contents of URL**
   - URL: `https://<your-worker>.workers.dev/api/sms`
   - Method: `POST`
   - Headers: `Authorization: Bearer <INGEST_TOKEN>`
   - Request Body: `JSON` → key `sms`, value **Shortcut Input**
3. **Run Immediately**, notifications off.

No app launch, no paste screen — the SMS lands in the inbox and the PWA picks it
up next time it's open.

## Not carried over

- **Face ID lock** → will be a PIN or WebAuthn; noticeably clunkier than `LAContext`.
- **Local-only privacy.** SMS text now transits your Worker. It's your own
  Cloudflare account rather than a third party, but it is no longer on-device only.
