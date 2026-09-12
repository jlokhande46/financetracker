# FinanceTracker — PWA

Web port of the iOS app. Exists because free Apple provisioning re-signs every
7 days, which kept breaking tracking continuity. An installed PWA never expires.

**Status: feature-complete against the iOS app.** Dashboard, transactions feed
with review, PDF statement import, recurring bills, budgets, goals, net worth
with manually-tracked holdings, analytics (50/30/20), Web Push reminders and the
app lock are all in. The Swift app in `../FinanceTracker` still runs and is
unaffected by anything here.

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
cd web
npm install
npm run dev          # http://localhost:5173
npm run typecheck    # app, service worker and Worker — three separate programs
npm test
```

`npm run dev` is enough to use the app: it stores everything in the browser's
IndexedDB, so it works with no backend at all. The Worker is only needed for
SMS capture and push notifications.

Three tsconfigs, not one: a `/// <reference lib="webworker" />` applies to the
whole compilation, so mixing the service worker in with the app turned `window`
into `never` for every client file.

## Hosting the app

Any static host works — the build is plain files. Two things it must have:
**HTTPS** (no service worker, no PWA install, no push without it) and, on iOS,
the ability to be added to the Home Screen, which is what unlocks Web Push and
lifts Safari's 7-day storage cap.

`BASE_PATH` controls where the app expects to live. It defaults to `/`; set it
when serving from a subpath, and the assets, manifest `start_url`/`scope` and
service-worker scope all follow:

```bash
npm run build                              # served at /
BASE_PATH=/financetracker/ npm run build   # served at /financetracker/
```

**Cloudflare Pages** is the path of least resistance here, since the Worker is
already on Cloudflare: connect the repo, set the build directory to `web`, the
command to `npm run build`, the output to `dist`. Free for private repos, serves
at the root so `BASE_PATH` stays default.

**GitHub Pages** works too — `.github/workflows/pages.yml` builds and publishes
on every push to `main` that touches `web/`, setting `BASE_PATH` to the repo
name automatically. Enable it once under Settings → Pages → Source: **GitHub
Actions**. Note that Pages on a *private* repo needs a paid GitHub plan; on the
free plan the repo has to be public, which publishes the source (including the
seeded card last-4s in `db/seed.ts`) but never any of your data — that only ever
exists in your own browser.

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

## The app lock

Settings → Privacy turns on a WebAuthn platform authenticator — Face ID, Touch
ID, or the device passcode — asked for on launch and again after the app has
been backgrounded for 30 seconds.

Be clear about what it is. It guards a **screen, not the data**: IndexedDB stays
readable to anything that can open devtools on an unlocked device, and with no
server there is nothing to verify the assertion signature against. `LAContext`
in the Swift build had the same property — the protection there was the OS's,
not the lock's — it is only more obvious here. What it stops is the person who
picks up your unlocked phone, which is the threat that actually happens.

Three decisions worth knowing about:

**A short absence curtains, a long one re-locks.** The Swift app re-locked the
instant it backgrounded. Flipping out to the SMS app to copy an OTP and straight
back is normal use of this thing, and demanding Face ID for it is how a lock gets
switched off for good — so under 30 seconds the app blurs behind a curtain
(which is also what the app switcher screenshots) and keeps its state, and over
30 seconds it demands the biometric again. Past that point nothing behind the
lock is even mounted, so there is no ledger in the DOM to screenshot.

**The toggle verifies in both directions.** Enabling without authenticating is
how you end up behind a lock you can't satisfy; disabling without authenticating
means whoever is holding the phone can just switch it off. The iOS toggle did
the same.

**There is a way out, and it appears only after three failed attempts.** Safari
reports a cancelled prompt and a vanished credential identically, so a cleared
passkey, a restored backup, or a new phone is indistinguishable from a fumbled
unlock — and a finance app with no account and no reset email would otherwise
lock you out of your own ledger permanently. The escape removes the lock and
nothing else; no transaction is touched. Yes, that means someone holding the
device can eventually get in, which is the same admission as the first
paragraph.

Push and the lock are independent: reminders keep arriving while the app is
locked, since they are sent from the Worker and never carry an amount.

## Not carried over

- **Local-only privacy.** SMS text now transits your Worker. It's your own
  Cloudflare account rather than a third party, but it is no longer on-device
  only. Reminder text does too — though not your transactions, which never
  leave the browser.
