# FinanceTracker — PWA

Web port of the iOS app. Exists because free Apple provisioning re-signs every
7 days, which kept breaking tracking continuity. An installed PWA never expires.

**Status: feature-complete against the iOS app.** Dashboard, transactions feed
with review, PDF statement import, recurring bills, budgets, goals, net worth
with manually-tracked holdings, analytics (50/30/20), and Web Push reminders are
all in. The Swift app in `../FinanceTracker` still runs and is unaffected by
anything here.

The one thing not carried over is the Face ID lock — see the end of this file.

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

Note what the server does *not* hold. The ledger stays in IndexedDB; the app
works out which reminders it wants from its own data and uploads only their
text and send times:

```
PWA  --(title, body, send_at)-->  D1 reminders  --hourly cron-->  Web Push
```

So the cron can send "Rent is due tomorrow" without the server ever seeing a
transaction. Each upload replaces the pending set, which is what makes a bill
you just marked paid stop nagging rather than needing its reminders cancelled
one by one.

## Layout

```
web/
├── src/
│   ├── domain/          types, categories, 50/30/20, analysis, bills, budgets,
│   │                    goals, reminder schedule, money tips
│   ├── parsing/         SMS parsers (8 bank formats) + PDF statement parser
│   ├── categorization/  merchant normaliser + classifier cascade
│   ├── ingest/          dedup -> parse -> normalise -> classify -> store
│   ├── db/              Dexie (IndexedDB) schema + paged reads + seed
│   ├── sync/            server config, inbox drain, push, schedule upload
│   ├── state/           feed pagination, grouping, mutations, plan hook
│   ├── ui/              screens (Dashboard, Transactions, Plan, Analytics,
│   │                    Settings, PDF import)
│   └── sw.ts            service worker — precache + the push handler
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
here, along with the bill-cycle maths and the push crypto.

```bash
npm test
```

Two of those suites are worth calling out:

- **`pdfParser.test.ts`** pins the actual statement rows that drove each fix:
  the BookMyShow row whose reward-points column got read as a ₹14 credit, the
  Federal column heuristic and why it's bank-gated, and the footer text that
  used to flip the last transaction of a statement into a credit.
- **`worker/src/webpush.test.ts`** decrypts what the Worker encrypts, playing
  the receiving browser. RFC 8291 is implemented by hand here (the `web-push`
  package needs Node crypto), and a mistake in it is invisible: the push
  service accepts the bytes and the phone silently shows nothing.

## Local dev

```bash
npm install
npm run dev          # PWA
npm run typecheck    # app, service worker and Worker — three separate programs
```

Three tsconfigs, not one: a `/// <reference lib="webworker" />` applies to the
whole compilation, so mixing the service worker in with the app turned `window`
into `never` for every client file.

## Deploying the backend

```bash
cd worker
npx wrangler d1 create financetracker      # put the id in wrangler.toml
npx wrangler d1 execute financetracker --file=schema.sql
npx wrangler secret put INGEST_TOKEN       # any long random string
npx wrangler deploy
```

Free tier covers a single-user app comfortably.

### Notifications

```bash
npm run vapid                              # prints a key pair
cd worker
npx wrangler secret put VAPID_PUBLIC_KEY
npx wrangler secret put VAPID_PRIVATE_KEY
npx wrangler secret put VAPID_SUBJECT      # mailto:you@example.com
```

Push stays off until all three are set. Then turn it on in Settings →
Notifications; there's a **Send a test notification** button so setup is
verifiable in one tap rather than by waiting for a bill.

On iOS this only works for an **installed** PWA (Share → Add to Home Screen,
iOS 16.4+). In a Safari tab the API is simply absent, and Settings says so
rather than showing a button that does nothing.

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

## What the Plan tab does

The recurring bills the user asked for — rent, electricity, postpaid and the
card settlements monthly, the gas cylinder every second month — plus budgets and
savings goals. Three things in it are less obvious than they look:

**A bill is paid when a transaction settles it, not when a date passes.** Marking
one paid opens a ranked shortlist of debits near the due date; picking one links
it. The list is deliberately generous and only preselects a confident match,
because silently linking the wrong payment marks a bill paid that isn't.

**Reminders start after salary lands and stop when everything's settled.**
Nagging on the 1st about a bill you can't pay until the 3rd is noise. The
cadence then ramps from one a day, to two, to three once overdue.

**A day past the end of a short month clamps rather than rolls over.**
`new Date(2026, 1, 31)` is 3 March; a bill due on the 31st has to land on 28
February. The Swift build had to learn the same lesson.

## Net worth

Assets (cash + holdings) minus card outstanding, with a monthly trend.

Holdings are entered by hand and there is **no live NAV fetch**, on purpose:
every Indian quote API wants a key, most rate-limit, and a portfolio that
silently stops updating is worse than one you knowingly refresh. So the UI
leans on saying how stale each figure is instead of pretending it's live, and
flags anything older than 45 days.

Two smaller judgements worth knowing about:

- A holding with no cost basis still counts towards net worth; it just shows no
  return. Gold bought at a price nobody remembers is still worth something. The
  card then says what share of the portfolio the stated gain actually speaks
  for, rather than implying it covers everything.
- History keeps one point per month — the latest — not one per app launch.
  Paying a card and then being paid inside a single month would otherwise turn
  the trend into a sawtooth.

Balances are *derived*: opening balance combined with that account's
transactions. Tap any account or card on the dashboard to set its opening
balance, which is what the iOS build never let you do — its net worth read off
seeded sample numbers that never updated.

## Not carried over

- **Face ID lock.** The web equivalent is WebAuthn with a platform
  authenticator, which does reach Face ID on iOS — but it guards a screen, not
  the data, since IndexedDB stays readable to anything with the device unlocked.
  `LAContext` had the same property; it's just less obvious here. Hide amounts
  covers the shoulder-surf case in the meantime.
- **Local-only privacy.** SMS text now transits your Worker. It's your own
  Cloudflare account rather than a third party, but it is no longer on-device
  only. Reminder text does too — though not your transactions, which never
  leave the browser.
