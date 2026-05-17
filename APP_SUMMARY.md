# FinanceTracker — Architecture Summary for AI Agents

This document gives an agent the mental model needed to make changes without re-reading the whole codebase. Read this first, then jump to specific files via the index at the bottom.

## What this app is

A single-user iOS personal finance tracker, India-focused. Owner uses an iPhone, sees SMS from HDFC / ICICI / SBI / Federal banks, and wants every transaction captured + categorised + slotted into a 50/30/20 budgeting frame against long-term goals.

**Non-goals**: multi-user collaboration, sharing, multi-currency, server backend.

## Tech stack

- **Swift 5.10 + SwiftUI**, iOS 17.0+ target, **dark-mode primary** (light is opt-in via theme picker).
- **SwiftData** persistence (`@Model` classes + `ModelContext` per repository).
- **`@Observable` macro** for view models — NOT `ObservableObject` (this distinction matters).
- **No external SPM dependencies**. Apple frameworks only (SwiftUI, SwiftData, Charts, PDFKit, LocalAuthentication, UserNotifications, UniformTypeIdentifiers).

## Layered architecture

```
View (SwiftUI)
  ↓ bound to
ViewModel (@Observable, @MainActor)
  ↓ uses
Repository (@MainActor; wraps ModelContext)
  ↓ reads/writes
@Model (SwiftData)
  ↔ converted to/from
Entity (Swift value type, used in domain logic and views)
```

Every layer transition crosses an entity ↔ model boundary. **Views never touch `@Model` types directly** — always entities.

### Why entities + models (vs. just `@Model`)

- Entities are value types: cheap to pass around, safe to diff, work in SwiftUI animations.
- Models are reference types tied to a `ModelContext`: mutating one outside its context's main actor blocks throws.
- Repositories own the conversion. View models never see `@Model`.

## Dependency injection

Single root `AppContainer` (class, `@MainActor`, NOT `ObservableObject`):

```swift
class AppContainer {
    let transactionRepo: TransactionRepositoryImpl
    let accountRepo: AccountRepositoryImpl
    let budgetRepo: BudgetRepositoryImpl
    let cardStatementRepo: CardStatementRepositoryImpl
    let goalRepo: GoalRepositoryImpl
    let billCycleManager: BillCycleManager
}
```

Injected via custom `EnvironmentKey` returning `AppContainer?`. Views read it with `@Environment(\.appContainer)`. View models are constructed once in `ContentView.task` with explicit repo dependencies.

`MerchantRuleStore.shared` is a singleton (touched from too many code paths — classifier, normalizer, parser). It attaches to the same `ModelContext` at app launch via `attach(modelContext:)`.

## Data model

### Entities (Domain/Entities/)

- **`TransactionEntity`** — the central object. Has `amount`, `type` (debit/credit), `merchantRaw` (as parsed from SMS/PDF), `merchantName` (display, possibly user-renamed), `categorySlug`, `date`, `source` (sms/pdf/manual), `confidence` (0-1), `isConfirmed`, `accountId?`, `intentOverride?`, plus optional fields (notes, tags, upiRef, bankRef, rawContent).
  - `needsReview` computed: `!isConfirmed && confidence < 0.85`
  - `effectiveIntent` computed: user override wins, else category default.
- **`AccountEntity`** — bank accounts and credit cards. Has `last4`, `creditLimit?`, `statementDay?`, `dueDay?` (for CC cycle automation).
- **`CategoryEntity`** — 26 system categories. Has `intent: CategoryIntent?` mapping to Needs/Wants/Savings. Income and Transfer categories return `nil`.
- **`CategoryIntent`** — enum `.need | .want | .saving`. Carries `targetPercent` (50/30/20).
- **`GoalEntity`** — `name`, `type` (travel/home/vehicle/…), `targetAmount`, `currentAmount`, `targetDate?`, `monthlyRequired` computed.
- **`CardStatementEntity`** — `accountId`, `statementDate`, `dueDate`, `totalDue`, `isPaid`, `daysUntilDue` computed.
- **`BudgetEntity`** — monthly category budget.

### SwiftData models (Data/Models/)

Mirror the entities. SwiftData auto-migrates new optional fields (no manual migrations have been needed yet). All `@Model` properties carry property-level defaults so future CloudKit enabling doesn't require code changes.

Critical: **`Decimal` ↔ `Double` round-trip via `Decimal(string: String(amount))`** (lossless) and `NSDecimalNumber(decimal:).doubleValue`. Direct `Decimal(amount)` would introduce floating-point drift.

### Repositories (Data/Repositories/)

Each repository:
- Holds a `ModelContext`.
- Exposes typed CRUD methods that return/accept entities.
- Uses a `persistChanges()` helper instead of silent `try? modelContext.save()` (the helper logs `assertionFailure` in debug).
- `fetchForMonth` etc. use explicit `if/else` branches for date predicates — `#Predicate` doesn't support runtime composition.

Notable: `TransactionRepositoryImpl.bulkRecategorize(merchantRaw:merchantNameKey:newSlug:)` — single save updates every matching transaction. Powers the "Fix past transactions too" toggle in Review.

## Critical subsystems

### SMS parsing (`Infrastructure/Parsing/SMSParser.swift`)

6 bank-specific regex-based parsers run in order of precision before falling back to generic patterns. Each returns a `ParsedSMSResult { amount, type, merchantRaw, last4?, date?, upiRef?, bankRef? }`.

Add a new bank: write one private function returning `ParsedSMSResult?` and add it to `parse(_:)`'s ordered list.

### PDF parsing (`Infrastructure/Parsing/PDFStatementParser.swift`)

1. **PDFKit text extraction** — gets raw text page-by-page.
2. **Multi-line record stitching** (`groupLinesIntoRecords`) — concatenates continuation lines onto the previous record. A new record begins at any line starting with a date. Without this, Federal Bank rows (3-line records) drop silently.
3. **Column-scrambled detection** (`recordsAppearColumnScrambled`) — if PDFKit read the table column-first (HDFC Savings symptom: 4+ dates with 0 amounts per record), parsing bails honestly rather than emitting garbage.
4. **`parseTransactionLine`** per record:
   - Extract date (and optional trailing time + value-date).
   - Extract amounts from **post-date substring only**, with `allowWholeNumbers: true` (safe because dates are already consumed).
   - Validate narration: ≥3 chars, contains letters, not in `junkSubstrings` (finance charges, GST, etc.).
   - Infer debit/credit via `inferAmountAndType`.
5. **Direction inference** (`inferAmountAndType`) — ordered rules:
   - **Cr/Dr suffix on amount** (when row has ≤3 amounts; for 4+ amounts the suffix is on balance, not txn).
   - **SBI `C` / `D`** as last char of line.
   - **HDFC `+` prefix** within 4 chars before amount.
   - **Column detection** when ≥2 non-balance amounts and exactly one is non-zero → index 0 = withdrawal (debit), index 1 = deposit (credit).
   - **Strict credit keywords**: salary credit, refund, cashback, reversal, IMPS IN, NEFT IN.
   - **CC-payment shortcut**: `bppy cc`, `cc payment`, `payment received` → categorised as `cc_payment` (a transfer type, doesn't count as spend).
   - **Default**: debit, low direction-confidence → flagged for review.

**Amount regex** (`extractAmounts`): comma-grouped only (`\d{1,3}(?:,\d{2,3})+`) — never space-grouped, otherwise "14 747.50" gets misread as ₹14,747.50. Lookbehind/lookahead anchors prevent matching digits embedded in alphanumeric tokens like `S95818915`.

### Account auto-linking

In `SettingsView.handlePDFImport`:

1. Extract `accountLast4` from PDF text — multiple regex patterns try `XXXX XXXX XXXX 6624`, `Card ending 6624`, ICICI's `3747XXXXXXXX2001` etc.
2. If extracted last4 matches an existing account: use that.
3. Filename hint (`productHints`): `tataneu → 6624`, `regalia → 4493`, `saphirro → 2000`, etc.
4. Bank + credit type fallback (only if exactly one credit card from that bank).
5. Bank-only fallback (only if exactly one account from that bank).

The matched account ID is written to every transaction in the bulk save.

### Categorisation (`Infrastructure/Categorization/`)

**`CategoryClassifier.classify(merchantName:amount:type:rawContent:)`** ordered:

1. **CC-payment shortcut** — credits whose narration contains `cc payment` / `bppy cc` etc. → `cc_payment` (skips amount-heuristic that would otherwise pick `salary`).
2. **User rule lookup** via `MerchantRuleStore.categoryForMerchant` — confidence 1.0.
3. **Built-in keyword rules** — list of `(merchant_substring, category_slug)` tuples — confidence 0.92.
4. **Amount-based heuristic** — credits ≥ ₹10K default to `salary`, confidence 0.6.
5. **Fallback** — `others` confidence 0.40 (this triggers Review).

**`MerchantNormalizer.normalize(_:)`**: trims, strips bank prefixes (`UPI-`, `POS-`, `NEFT-`, …), strips VPA (everything after `@`), strips trailing ref tokens, strips corporate suffixes (`Pvt Ltd`, etc.), then runs `aliasMap` lookup. **User rules win first** — `displayNameForMerchant` is consulted before any cleanup.

**`MerchantRuleStore`** (singleton attached to `ModelContext` at launch):
- `saveRule(merchant:categorySlug:displayName:)` — store name OR category OR both, keyed by normalised merchant string.
- `categoryForMerchant`, `displayNameForMerchant` — substring-match lookups (key contains lookup OR lookup contains key — longest match wins).
- `normalize(_:)` here aggressively strips: UPI prefixes, `@vpa`, digit runs ≥5 chars. So rule for `UPI-SWIGGY-...-123456789@oksbi` matches any future `Swiggy *` variant.

### Bill cycle automation (`Infrastructure/BillCycle/BillCycleManager.swift`)

Runs on every app launch + after each transaction save:

1. For each credit account with `statementDay` and `dueDay` set:
   - Compute the most-recent completed cycle.
   - Sum debits posted to that card in the cycle window.
   - If no `CardStatement` exists for that cycle, create one and schedule daily reminders via `NotificationManager`.
2. For each unpaid statement, look for a `cc_payment` transaction posted after the statement date with amount within ±1%. If found, mark paid and cancel notifications.

Configure cycle days in `AccountDetailView` → "Billing Cycle" row → `EditCycleSheet`.

### Notifications (`Infrastructure/Notifications/NotificationManager.swift`)

- `scheduleReminders(for: CardStatementEntity)` — one notification per day from today through due date, max 7 ahead. Body adjusts: "Due TODAY" → "Due TOMORROW" → "due in N days". `interruptionLevel: .timeSensitive` on due-today.
- `scheduleBudgetAlerts(for: budgets)` — fires when a budget crosses 80% (warning) or 100% (over). Deduped via `UserDefaults` key per budget per period.
- `cancelReminders(for: statementId)` — fires on mark-paid.
- `cancelAll()` — fires on Clear All Data.

### Deep linking (`App/DeepLinkHandler.swift`)

Singleton, `@Observable`. `handle(_ url:)` parses `financetracker://import?sms=<encoded>`, deduplicates by SMS hash within a 10-second window (kills double-fires from Shortcuts/iOS), sets `pendingSMSText`.

`ContentView` and `TransactionFeedView` both observe `pendingSMSText`: tab-switch and sheet-open respectively. `SMSImportView` reads `initialSMS` on `.task` and auto-saves.

Second-level dedup: `SMSImportView.autoParseAndSave` checks for any transaction with matching `rawContent` saved in the last 2 minutes before inserting.

### Quick Review (`Features/Transactions/Components/QuickReviewSheet.swift`)

Walks through `pendingReviewTransactions` one card at a time. Snapshots the list on `init` so parent mutations during review don't shift indices. Each card has:
- Editable merchant name TextField (`.id(index)` forces fresh state per row).
- Category picker grid.
- "Remember name" + "Remember category" + "Fix past transactions too" toggles (all default ON).
- Sticky action bar: `← prev · 🗑 delete · Confirm · → skip`.

`onConfirm` callback signature: `(TransactionEntity, newName, newSlug, rememberName, rememberCategory, applyToPast) -> Void`. Routes to `TransactionListViewModel.confirmReview` or `DashboardViewModel.confirmReview`.

### Per-transaction intent override (`Features/Transactions/Components/TransactionRowView.swift`)

Custom `DragGesture` (because `.swipeActions` is List-only and the feed uses `LazyVStack`):
- Drag right → reveals green **Need** label from left edge.
- Drag left → reveals amber **Want** label from right edge.
- Past 80pt commit threshold: haptic tick + on release fires `onSetIntent(.need / .want)`.
- Past 140pt: resistance kicks in so the row never flies off-screen.
- Tap → opens detail. Long-press → context menu with Need/Want/Saving/Clear.

Also a tappable inline chip in the subtitle that cycles `(default) → Need → Want → Saving → (default)`.

Income rows skip intent UI entirely.

### Smart insights (`Features/Dashboard/Components/SmartInsightsCard.swift`)

Heuristic engine — not ML. Called from `DashboardViewModel.load()` with current month + trailing 6 months + goals + monthly income. Surfaces:

1. **Wants > 35% of spend** → "Trim ₹X to hit 30% target."
2. **Savings rate < 10%** → "Aim for 20% to compound faster."
3. **Top wants category** → "20% cut frees ₹X/mo."
4. **Goal projection** for each goal — short by ₹X/mo OR will-hit-in-N-months.
5. **3+ subscriptions** → "Audit them, one unused = pure savings."
6. **Anomaly detection** — per-category z-score vs 6-month mean/stddev; flags strongest >1.5σ spike.
7. **Recurring discovery** — merchants appearing in ≥3 distinct months at within-15% amounts, not already tagged subscription/EMI.
8. **Goal acceleration** — short goal + dominant wants category → "Cut X by N% to hit goal."

## Conventions / gotchas

- **Never `ObservableObject`** — every reactive class uses `@Observable`. Same for `AppContainer` (plain class, accessed via custom `EnvironmentKey`).
- **Decimal everywhere for currency.** Conversion only at SwiftData boundary.
- **Confidence-driven review**: `needsReview = !isConfirmed && confidence < 0.85`. User-rule classifications get confidence 1.0 → auto-confirm, skip review.
- **Sample data**: seeded on first launch unless `seedDisabled` UserDefaults flag is set (toggled by Clear All Data). Real card last4s are synced unconditionally via `accountRepo.syncUserCards()` every launch.
- **Light-theme caveat**: bg / text colors are adaptive via `Color.adaptive(dark:light:)`. Brand and category palettes stay constant.
- **PDFs in `unlocked/` are gitignored** — they contain real bank statement data.

## File index

```
App/
  FinanceTrackerApp.swift       App entry. ModelContainer config. Theme. Face ID lock overlay. Deep link handler wiring.
  AppContainer.swift            DI container. Repo init order. clearAllData(). syncUserCards() + billCycleManager.runDailySweep() on launch.
  ContentView.swift             Tab bar. VM lifecycle. Deep-link tab switch. Dynamic tab-bar styling (adapts to light/dark).
  DeepLinkHandler.swift         financetracker://import?sms=... → pendingSMSText, with 10s hash dedup.

Domain/Entities/
  TransactionEntity.swift       The big one. Has effectiveIntent for 50/30/20.
  AccountEntity.swift           statementDay, dueDay for cycle automation.
  CategoryEntity.swift          26 system categories + .intent map.
  CategoryIntent.swift          Needs/Wants/Savings + 50/30/20 targetPercent.
  GoalEntity.swift              Plus GoalType enum (icons + colors).
  CardStatementEntity.swift     daysUntilDue computed.
  BudgetEntity.swift            Monthly category limits.

Data/Models/                    SwiftData @Model mirrors. All have property-level defaults.
Data/Repositories/              ModelContext wrappers. persistChanges() helper.
Data/SampleData.swift           Real card last4s. Seeded on first launch.

Infrastructure/
  Parsing/SMSParser.swift                       6 bank-specific parsers + generic fallbacks.
  Parsing/PDFStatementParser.swift              Multi-line stitching, column-aware inference, column-scrambled bail-out.
  Categorization/CategoryClassifier.swift       5-step classification cascade.
  Categorization/MerchantNormalizer.swift       Alias map + cleanup pipeline.
  Categorization/MerchantRuleStore.swift        Singleton; learned name + category rules.
  Notifications/NotificationManager.swift       Card-due + budget-alert scheduling.
  BillCycle/BillCycleManager.swift              Statement creation + auto-mark-paid.
  Auth/BiometricAuthService.swift               LAContext wrapper. Returns BiometricKind.

Features/
  Dashboard/                    Summary, top merchants, cards-due, smart insights.
  Transactions/                 Feed, detail, Quick Review, SMS import, Add Transaction.
  Transactions/Components/
    TransactionRowView.swift                Custom swipe gesture + intent chip.
    QuickReviewSheet.swift                  Snapshot-based one-at-a-time review flow.
    SMSImportView.swift                     Auto-mode (deep link) + manual paste.
    CategoryReviewSheet.swift               Single-transaction category change.
    EditCategorySheet.swift                 Detail-view category change + "Fix past" toggle.
  Analytics/                    50/30/20 card, trends, category breakdown.
  Budgets/                      Budgets + Goals section.
  Goals/                        Goal CRUD + contribution sheet.
  Accounts/                     AccountDetailView, EditCycleSheet.
  Settings/                     Profile, theme, Face ID, PDF import, clear data.
  Lock/LockScreenView.swift     Face ID gate on launch + on background.
  Onboarding/                   First-launch flow.

Shared/                         Reusable components (ToastView, CategoryIconView, EmptyStateView, …).
DesignSystem/                   AppColors (adaptive), AppFonts, AppSpacing.
```

## Adding a new bank

1. Drop a sample SMS in `SMSParser.swift` as a comment.
2. Write a private parser function `parseXBankYProduct(_ msg:)`.
3. Add to `parse(_:)`'s ordered call list before the generic fallbacks.
4. If the bank has a corresponding PDF format that's column-scrambled by PDFKit, add no PDF support (rely on SMS).
5. If the PDF is parseable but uses a unique direction marker, extend `inferAmountAndType` in `PDFStatementParser.swift`.

## Adding a new category

1. Append to `CategoryEntity.system` with a new slug, name, SF Symbol icon, hex color, and `sortOrder`.
2. Map it to a `CategoryIntent` in the `intent` computed property switch.
3. If a common merchant should classify here, add a tuple to `CategoryClassifier.merchantRules`.

## Apple Shortcuts integration

URL scheme `financetracker://import?sms=<URL-encoded text>`. Configure once per user — see README. The app does all dedup on its end (DeepLinkHandler hash window + SMSImportView rawContent recency).
