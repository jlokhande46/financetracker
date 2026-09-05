# FinanceTracker

Personal finance tracking for the Indian market. Every bank transaction gets
captured automatically — via SMS, PDF statement, or manual entry — then
categorised, linked to the right card, and fed into a 50/30/20
needs/wants/savings view alongside per-goal projections.

This repo holds **two implementations** of that idea.

| | `FinanceTracker/` | `web/` |
|---|---|---|
| Stack | Swift / SwiftUI / SwiftData | TypeScript / React / IndexedDB |
| Status | Complete, feature-rich | **Active development** |
| Runs for | 7 days, then needs re-signing | Forever once installed |
| SMS capture | App Intent (locked-phone, silent) | Shortcuts → HTTPS POST → Worker |
| Notifications | Local (`UNCalendarNotificationTrigger`) | Web Push from a cron |
| Storage | On-device only | IndexedDB + Cloudflare D1 |
| Docs | [IOS_APP.md](IOS_APP.md) | [web/README.md](web/README.md) |

## Why there are two

Free Apple provisioning re-signs every **7 days**. For an app you rely on daily,
that meant reinstalling constantly and losing tracking continuity each time. An
installed PWA never expires, and works on Android and desktop too.

The iOS app isn't abandoned — it still runs, and it's the **reference
implementation**. Its parsers encode a lot of hard-won detail about how Indian
bank SMS and credit-card PDFs actually look, and that knowledge is what the web
port is carrying across.

## They don't interfere

The Xcode project uses a filesystem-synchronized group scoped to
`path = FinanceTracker`, so `web/` is invisible to Xcode — it won't appear in
the navigator or get compiled. Likewise nothing in `web/` reads the Swift
sources. You can work on either without touching the other.

## Getting started

**iOS** — open `FinanceTracker.xcodeproj` in Xcode 15+, set your signing team,
build to a device. See [IOS_APP.md](IOS_APP.md).

**Web**
```bash
cd web
npm install
npm test          # 25 tests over the SMS parsers + classifier
npm run dev
```
See [web/README.md](web/README.md) for the backend and Shortcut setup.

## Reference docs

These describe behaviour the web port still has to match:

- [PRIMARY_FEATURES.md](PRIMARY_FEATURES.md) — the 30-item acceptance checklist
- [APP_SUMMARY.md](APP_SUMMARY.md) — architecture overview
- [PROGRESS.md](PROGRESS.md) — dated change log, including several bug
  post-mortems worth reading before touching the parsers
