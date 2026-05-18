# PRIMARY FEATURES — Acceptance Checklist

The 30 capabilities below are what FinanceTracker is supposed to do. Each one
should work on every build of `main`. Treat a regression here as a release-
blocking bug.

Grouped by area. Numbers are stable so you can refer to "PF-12" or
"#12 — Quick Review" in conversations.

---

## Capture (1–6)

1. **SMS auto-import via App Intent** — `LogBankSMSIntent` is invoked from
   Shortcuts. Runs silently with the phone locked (`openAppWhenRun = false`).
   Writes the SMS to the App Group queue; the main app drains it on next
   foreground via `AppContainer.processPendingSMS()`.

2. **SMS auto-import via URL scheme** — `financetracker://import?sms=<URL-encoded text>`
   opens the app, jumps to the Transactions tab, runs `autoParseAndSave`,
   saves and dismisses. Deduplicates by SMS hash within a 10-second window
   and by `rawContent` recency within 2 minutes.

3. **Bank parsers** — each pattern must round-trip correctly:
   - HDFC Savings sent: `Sent Rs.X From HDFC Bank A/C *XXXX To MERCHANT On DD/MM/YY Ref XXX`
   - HDFC Savings credited: `Credit Alert! Rs.X credited to HDFC Bank A/c XXNNNN on DD-MM-YY from VPA xxx (UPI nnn)`
   - HDFC CC Tata Neu Rupay UPI: `Txn Rs.X On HDFC Bank Card XXXX At MERCHANT by UPI XXX On DD-MM`
   - HDFC CC Regalia: `Spent Rs.X On HDFC Bank Card XXXX At MERCHANT On YYYY-MM-DD:HH:MM:SS`
   - ICICI Sapphiro CC: `INR X spent using ICICI Bank Card XXNNNN on DD-Mon-YY on MERCHANT`
   - SBI Cashback CC: `Rs.X spent on your SBI Credit Card ending XXXX at MERCHANT on DD/MM/YY`
   - Federal Bank received: `received INR X in Account XXXXX. … sent by NAME on Month DD, YYYY`
   - Federal Bank sent: `Rs X sent via UPI on DD-MM-YYYY at HH:MM:SS to MERCHANT.Ref:NNN … -Federal Bank`

4. **Manual Add Transaction** — amount, debit/credit toggle, merchant,
   category, date, account picker, notes, tags with autocomplete.

5. **PDF Statement Import** — `PDFImportConfirmSheet` always shows after parse
   with a file summary (transaction count, debit & credit totals, detected
   bank). Account picker is always populated; if empty, self-heals via
   `syncUserCards()` on `onAppear` and offers a "Restore default cards"
   button. The Import button stays disabled until an account is chosen when
   transactions exist.

6. **PDF bank-specific parsing**:
   - HDFC Tata Neu / Regalia → `parseHDFCCreditCardRow` (handles `+ N C AMOUNT`
     rewards format and `+ C AMOUNT` credits)
   - ICICI Sapphiro → `CR` suffix on amount → credit
   - SBI Cashback → `C` / `D` last char on row → credit / debit
   - Federal Bank savings → column detection (withdrawal/deposit/balance)
   - HDFC Savings → honestly skipped (`recordsAppearColumnScrambled`)

---

## Auto-classification (7–11)

7. **Merchant Normalizer** — strips `UPI-` / `POS-` / `NEFT-` / `IMPS-` /
   `RTGS-` / `PAY*` / `CAS*` prefixes; drops VPA handles (everything after
   `@`); strips trailing ref-token chains; removes corporate suffixes
   (`Pvt Ltd`, ` India`, ` Co`); applies the alias map for known merchants.

8. **Category Classifier cascade**:
   0. CC-payment shortcut (`bppy cc`, `cc payment`, `payment received` …)
      → `cc_payment` at confidence 1.0
   1. User rule (`MerchantRuleStore.categoryForMerchant`) → 1.0
   2. Built-in keyword rule (`(merchant_substring, slug)` tuples) → 0.92
   3. Amount heuristic (credit ≥ ₹10K → `salary`) → 0.6
   4. Fallback → `others` → 0.4 (triggers Review)

9. **User rules apply at import time** — a "Remember" tap saves both display
   name AND category to `MerchantRuleStore`. The next import of the same
   merchant gets the saved name (via `MerchantNormalizer.displayNameForMerchant`)
   and saved category (via `categoryForMerchant`) at confidence 1.0 — row
   auto-confirms and skips Review entirely.

10. **Account auto-linking for SMS** (`SMSImportView.linkAccount`):
    1. last4 from parser → exact match
    2. Bank keyword → known last4 (`federal bank → 8708`)
    3. Bank keyword → single account from that bank
    Falls through silently if nothing matches; row saves with `accountId = nil`
    and the Re-link Orphans utility can fix it later.

11. **Account auto-linking for PDF** (`SettingsView.suggestAccount`):
    1. last4 from parsed PDF text
    2. Filename product hint (`tataneu → 6624`, `regalia → 4493`, etc.)
    3. Single credit card from detected bank
    4. Single account from detected bank
    Suggestion is pre-filled in `PDFImportConfirmSheet`; user can override.

---

## Review & edit (12–15)

12. **Quick Review** (Review All) — `QuickReviewSheet` walks pending reviews
    one card at a time, snapshot-based so parent mutations don't shift
    indices. Each row supports: editable merchant name, category picker,
    **editable tags with autocomplete**, prev/delete/confirm/skip action
    bar. Remember-name, Remember-category, "Fix past transactions too" all
    default ON.

13. **Transaction Detail** — editable merchant name TextField, account
    picker chip row, change-category sheet with apply-to-past toggle,
    notes, tags, recurring toggle, raw SMS view, delete.

14. **Per-transaction intent override** — custom drag gesture (not
    `.swipeActions`, which is List-only):
    - Drag right → green Need
    - Drag left → amber Want
    - 80pt commit threshold + haptic
    - Tap inline chip cycles `(default) → Need → Want → Saving`
    - Long-press for context menu
    Income rows skip the intent UI.

15. **Tap a `#tag` chip on a row** to toggle that tag in
    `viewModel.selectedTags`. Same set the filter sheet writes to.

---

## Filters & display (16–19)

16. **Transaction filter sheet** — Type, Category, Source, **Tags
    (multi-select chip cloud)**, Date Range, Amount Range.

17. **Active filter banner** appears above the feed when any filter is on;
    shows `#tag` markers when tag filters are active.

18. **50/30/20 Needs/Wants/Savings card** in Analytics — uses
    `effectiveIntent` (per-transaction override > category default).

19. **Insight dismissal persists** via UserDefaults key `dismissedInsightIDs`.
    `DashboardViewModel.visibleInsights` filters them out;
    `dismissInsight(_:)` writes back. Stable insight IDs (FNV-1a hash of
    type + month) survive pull-to-refresh and app relaunch.

---

## Goals & budgets (20–22)

20. **Goals** — add / edit / delete in Budgets tab. Progress ring with
    percentage, target date, monthly contribution required, "Add
    contribution" flow.

21. **Budgets** — monthly per-category limits. Warning push notification
    at 80%, over-budget alert at 100% (deduped per period via
    UserDefaults).

22. **Card statement cycle** — set `statementDay` and `dueDay` on a credit
    account → `BillCycleManager.runDailySweep()` auto-creates a
    `CardStatement` for the most recent completed cycle (sum of debits in
    the window). Daily 9am reminder notifications until paid. Auto
    mark-paid when a `cc_payment` transaction within ±1% of the total due
    posts.

---

## Settings & developer (23–27)

23. **Theme picker** — System / Light / Dark.

24. **Face ID lock** — re-locks on background. Toggle verifies biometric
    before persisting so the user can't lock themselves out.

25. **Clear All Data** — deletes transactions, budgets, statements, goals,
    merchant rules; cancels notifications; sets `seedDisabled`.
    **Accounts immediately re-seed via `syncUserCards()`** because they
    represent real cards, not test data.

26. **Developer Options** (`Profile → Privacy & Security → Developer Options`):
    - **Merchant Rules** section: search, edit (display name + category),
      per-row delete, "Delete all"
    - **Diagnostics**: live counts for transactions, accounts, budgets,
      goals, card statements, pending SMS queue, dismissed insights
    - **Reset**: flush pending SMS queue (only when non-empty), restore
      dismissed insights (only when some are hidden), Restore default
      cards, Re-link orphan transactions

27. **PDF Import Confirm Sheet** — self-heals empty accounts on first
    appear by calling `syncUserCards()` once.

---

## Persistence guarantees (28–30)

28. **Accounts are always present** unless the user truly has zero on
    file. The auto-heal + Restore-default-cards button + Developer Options
    action all back this guarantee.

29. **Transaction → account link survives updates**.
    `TransactionRepositoryImpl.update()` persists every mutable field
    (amount, type, date, source, subcategory, isSplit, parentId, accountId,
    intentOverride, upiRef, bankRef, receiptURL, confidence, etc. — 18
    fields total).

30. **Insight IDs are stable** (FNV-1a hash of type + month) so dismissal
    isn't lost on refresh, month change, or relaunch.

---

## How to test a release

After pulling and clean-building:

1. `Profile → Developer Options → Diagnostics` — verify expected counts.
2. `Profile → Clear All Data` — confirm accounts come back.
3. `Profile → Import Statement` — pick a known PDF; verify all 6 from PF-6
   parse the right number of transactions with correct direction.
4. Run a known SMS through the Shortcut (or paste into SMSImportView) for
   each format in PF-3; verify it saves silently.
5. `Transactions → Review All` — confirm a row with Remember on, verify
   future imports of that merchant skip Review.
6. Swipe a row right (Need) / left (Want) — verify badge appears.
7. Tap a `#tag` chip on any row — verify feed filters.
