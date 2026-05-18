# PROGRESS

Running log of what's been built in FinanceTracker. Updated as work lands.
The acceptance bar for "done" is [PRIMARY_FEATURES.md](PRIMARY_FEATURES.md) —
**before changing anything, read both files and confirm your edit will not
regress an item there.** If it will, stop and discuss instead of shipping.

Companions:
- [PRIMARY_FEATURES.md](PRIMARY_FEATURES.md) — the 30-item acceptance checklist (PF-1 … PF-30)
- [APP_SUMMARY.md](APP_SUMMARY.md) — architectural overview for new agents
- [README.md](README.md) — user-facing description

---

## Working agreement for future edits

1. **Read PRIMARY_FEATURES.md first.** Every numbered item is a regression
   gate. If your change might affect any of them, verify with the runbook at
   the bottom of that file before claiming done.
2. **Don't refactor working features.** Bug fix = bug fix. No surrounding
   "while I'm here" cleanups that risk PF-N items.
3. **Update this file** when you complete a feature or fix. Add a dated entry
   under "Change log" and, if it satisfies/strengthens a PF item, note that.
4. **No silent removals.** If a PF item is intentionally being dropped or
   reshaped, edit PRIMARY_FEATURES.md in the same change and explain why in
   the commit.

---

## Status snapshot (as of 2026-05-18)

All 30 items in PRIMARY_FEATURES.md are implemented on `main`. The list below
maps each one to where it lives so reviewers can audit fast.

### Capture (PF-1 … PF-6) — ✅
- **PF-1** SMS via App Intent: [LogBankSMSIntent.swift](FinanceTracker/App/Intents/LogBankSMSIntent.swift),
  drained by `AppContainer.processPendingSMS()` on foreground.
- **PF-2** SMS via URL scheme: [DeepLinkHandler.swift](FinanceTracker/App/DeepLinkHandler.swift)
  → [TransactionFeedView.swift](FinanceTracker/Features/Transactions/TransactionFeedView.swift)
  → [SMSImportView.swift](FinanceTracker/Features/Transactions/Components/SMSImportView.swift)
  auto-mode. Cold-launch race fixed 2026-05-18 (see change log).
- **PF-3** Bank SMS parsers: [SMSParser.swift](FinanceTracker/Infrastructure/Parsing/SMSParser.swift)
  — all 8 patterns round-trip.
- **PF-4** Manual Add: [AddTransactionView.swift](FinanceTracker/Features/Transactions/Components/AddTransactionView.swift).
- **PF-5** PDF confirm sheet: [PDFImportConfirmSheet.swift](FinanceTracker/Features/Settings/Components/PDFImportConfirmSheet.swift)
  — self-heals empty accounts via `syncUserCards()` on appear.
- **PF-6** Bank PDF parsers: [PDFStatementParser.swift](FinanceTracker/Infrastructure/Parsing/PDFStatementParser.swift)
  — HDFC CC (`parseHDFCCreditCardRow`), ICICI Sapphiro (`CR` suffix), SBI
  (`C`/`D` last char + space-separated dates), Federal savings, HDFC Savings
  intentionally skipped.

### Auto-classification (PF-7 … PF-11) — ✅
- **PF-7** [MerchantNormalizer.swift](FinanceTracker/Domain/Services/MerchantNormalizer.swift).
- **PF-8** [CategoryClassifier.swift](FinanceTracker/Domain/Services/CategoryClassifier.swift)
  — 5-step cascade with cc_payment shortcut.
- **PF-9** Remembered name + category short-circuits Review:
  [MerchantRuleStore.swift](FinanceTracker/Domain/Services/MerchantRuleStore.swift)
  + import-time lookup in SMSImportView / PDF import flow.
- **PF-10** SMS account auto-link: `SMSImportView.linkAccount`.
- **PF-11** PDF account auto-link: `SettingsView.suggestAccount`.

### Review & edit (PF-12 … PF-15) — ✅
- **PF-12** [QuickReviewSheet.swift](FinanceTracker/Features/Transactions/Components/QuickReviewSheet.swift)
  — snapshot-based, editable name + category + tags, Remember defaults ON.
- **PF-13** [TransactionDetailView.swift](FinanceTracker/Features/Transactions/Components/TransactionDetailView.swift).
- **PF-14** Custom DragGesture intent override (not `.swipeActions`) in
  [TransactionRowView.swift](FinanceTracker/Features/Transactions/Components/TransactionRowView.swift).
- **PF-15** Tag chip tap → `viewModel.selectedTags` in TransactionRowView.

### Filters & display (PF-16 … PF-19) — ✅
- **PF-16** [TransactionFilterSheet.swift](FinanceTracker/Features/Transactions/Components/TransactionFilterSheet.swift)
  — includes tags multi-select chip cloud.
- **PF-17** Active filter banner in TransactionFeedView.
- **PF-18** [AnalyticsView.swift](FinanceTracker/Features/Analytics/AnalyticsView.swift)
  50/30/20 card uses `effectiveIntent`.
- **PF-19** Insight dismissal via UserDefaults `dismissedInsightIDs` in
  [DashboardViewModel.swift](FinanceTracker/Features/Dashboard/DashboardViewModel.swift).

### Goals & budgets (PF-20 … PF-22) — ✅
- **PF-20** Goals CRUD in [BudgetsView.swift](FinanceTracker/Features/Budgets/BudgetsView.swift).
- **PF-21** Budget warning + over-budget notifications via
  [NotificationManager.swift](FinanceTracker/Infrastructure/Notifications/NotificationManager.swift),
  deduped per period.
- **PF-22** [BillCycleManager.swift](FinanceTracker/Domain/Services/BillCycleManager.swift)
  — daily sweep, auto-create CardStatement, auto mark-paid on matching cc_payment.

### Settings & developer (PF-23 … PF-27) — ✅
- **PF-23** Theme picker in [ProfileView.swift](FinanceTracker/Features/Profile/ProfileView.swift).
- **PF-24** Face ID lock (verifies before persisting toggle).
- **PF-25** `AppContainer.clearAllData()` re-seeds accounts via `syncUserCards()`.
- **PF-26** [DeveloperOptionsView.swift](FinanceTracker/Features/Developer/DeveloperOptionsView.swift)
  — merchant rules editor, diagnostics, reset actions.
- **PF-27** PDFImportConfirmSheet self-heal — same file as PF-5.

### Persistence (PF-28 … PF-30) — ✅
- **PF-28** Auto-heal accounts (PF-5 + PF-25 + PF-26 Restore default cards button).
- **PF-29** `TransactionRepositoryImpl.update()` persists 18 fields incl. accountId.
- **PF-30** FNV-1a stable insight IDs in DashboardViewModel.

---

## Change log

### 2026-05-18 — SMS auto-mode cold-launch fix
**Symptom:** URL-scheme deep link from Shortcut opened the app and landed on
the "Paste SMS" screen with an empty textarea instead of auto-parsing
(PF-2 regression).

**Root cause:** `DeepLinkHandler.shared.pendingSMSText` was set during cold
launch *before* the `.onChange` listeners in `ContentView` and
`TransactionFeedView` mounted. SwiftUI's `.onChange` does not fire for the
initial value, so the sheet never presented; when it eventually did, the
content closure captured `initialSMS = nil` and `isAutoMode` was false.

**Fix:**
- `SMSImportView`: converted `isAutoMode` from a computed property
  (`initialSMS != nil`) to a `@State` seeded in `init` from
  `initialSMS ?? DeepLinkHandler.shared.pendingSMSText`. The `.task` block
  already falls back to the singleton when `initialSMS` is nil.
- `TransactionFeedView`: added `.onAppear` that presents the sheet if
  `pendingSMSText` is already set on first appearance.
- `ContentView`: added matching `.onAppear` that switches to the
  Transactions tab on cold launch.

**PF impact:** restores PF-2. No other PF item touched.

### 2026-05-17 — Developer Options
New view at `Profile → Privacy & Security → Developer Options`. Implements
PF-26: merchant rules editor (search/edit/delete), live diagnostics counts,
reset actions (flush pending SMS queue, restore dismissed insights, restore
default cards, re-link orphan transactions).

### 2026-05-17 — Clear All Data re-seeds accounts
`AppContainer.clearAllData()` now calls `accountRepo.syncUserCards()` after
the wipe. Implements PF-25 / PF-28. Closes the empty-account-picker bug
reported on PDF import after a reset.

### 2026-05-16 — Tags in Quick Review
`QuickReviewSheet` now exposes an editable tag field with autocomplete
backed by `allKnownTags`. Strengthens PF-12.

### 2026-05-15 — App Intent for locked-phone SMS
Cherry-picked the useful commits from PR #3: `LogBankSMSIntent` with
`openAppWhenRun = false`, App Group queue (`PendingSMSStore`), drained by
`AppContainer.processPendingSMS()` on foreground. Implements PF-1.

### 2026-05-14 — SBI Cashback PDF parsing
Updated `groupLinesIntoRecords` and `recordsAppearColumnScrambled` regex to
accept space-separated dates (`07 Apr 26`) in addition to slash/dash forms.
Restores PF-6 for SBI statements.

### 2026-05-13 — HDFC CC row parser
New `parseHDFCCreditCardRow` handles the
`DATE | TIME DESC [+ N] [+] C AMOUNT` layout used by Tata Neu and Regalia,
including the `+ N C AMOUNT` rewards format and `+ C AMOUNT` credits.
Implements PF-6 (HDFC CC).

### 2026-05-12 — PDF Import Confirm Sheet
Always shows after parse with file summary; account picker self-heals via
`syncUserCards()` on appear; "Restore default cards" button when empty;
Import disabled until account chosen. Implements PF-5 / PF-27.

### 2026-05-10 — Stable insight IDs
Insight IDs now FNV-1a hash of `type + month` so dismissal persists across
refresh, month change, and relaunch. Implements PF-19 / PF-30.

### 2026-05-09 — Per-transaction intent override
Custom `DragGesture` swipe in `TransactionRowView` (not `.swipeActions`,
which is List-only and clashed with the LazyVStack feed). 80pt threshold,
haptic, tap-to-cycle chip, long-press menu. Income rows excluded. Implements
PF-14.

### 2026-05-08 — Tag filters
Multi-select chip cloud in `TransactionFilterSheet`; active filter banner
shows `#tag` markers; row chip tap toggles selection. Implements PF-15 /
PF-16 / PF-17.

### 2026-05-07 — Merchant rules apply at import
Remember-name + Remember-category save into `MerchantRuleStore` at Review
time. Subsequent imports of the same merchant resolve to the saved
display name + category at confidence 1.0 and skip Review entirely.
Implements PF-9.

### 2026-05-05 — Federal Bank parsers
Both sent and received SMS templates plus PDF column-detection (withdrawal
/ deposit / balance). Implements PF-3 (Federal) and PF-6 (Federal).

---

## Open items / known gaps

- HDFC Savings PDF parsing is intentionally skipped because columns scramble
  on extraction (`recordsAppearColumnScrambled`). PRIMARY_FEATURES.md PF-6
  documents this as expected behavior, not a bug.
- No automated test suite covers PF items end-to-end. The runbook at the
  bottom of PRIMARY_FEATURES.md is the manual gate.
