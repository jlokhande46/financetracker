# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

Pure Xcode project — no SPM, no Makefile, no Fastfile. No test targets exist.

```bash
# Build from CLI
xcodebuild -scheme FinanceTracker -destination 'platform=iOS Simulator,name=iPhone 16' build

# Clean build
xcodebuild -scheme FinanceTracker clean build
```

Primary workflow: open `FinanceTracker.xcodeproj` in Xcode, build + run on device or simulator. No linting tools configured.

## Architecture

Clean Architecture + MVVM. Layer boundaries are strict:

```
View (SwiftUI)
  ↓ reads entities from
ViewModel (@Observable, @MainActor)
  ↓ calls
Repository (@MainActor, wraps ModelContext)
  ↓ reads/writes
@Model (SwiftData)   ↔   Entity (Swift value type)
```

**Views never touch `@Model` types.** Repositories own all entity ↔ model conversion.

### Dependency Injection

`AppContainer` (plain class, `@MainActor`, NOT `ObservableObject`) owns all repos. Injected via custom `EnvironmentKey`; views read with `@Environment(\.appContainer)`. VMs are constructed once in `ContentView.task`.

`MerchantRuleStore.shared` is a singleton attached to `ModelContext` at launch via `attach(modelContext:)`.

### Key Conventions

- **Always `@Observable`, never `ObservableObject`** — applies to every VM and reactive class.
- **`Decimal` everywhere for currency.** Conversion at SwiftData boundary only, via `Decimal(string: String(amount))` (lossless). Never `Decimal(doubleValue)`.
- **`persistChanges()` helper** in repos — use over silent `try? modelContext.save()`. Logs `assertionFailure` in debug on failure.
- **`#Predicate` limitation**: doesn't support runtime composition — use explicit `if/else` branches in fetch methods.
- Confidence-driven review: `needsReview = !isConfirmed && confidence < 0.85`. User-rule classifications get confidence 1.0 → auto-confirm.

## Critical Subsystems

### SMS Parsing (`Infrastructure/Parsing/SMSParser.swift`)

6 bank-specific parsers run in order before generic fallbacks. Returns `ParsedSMSResult { amount, type, merchantRaw, last4?, date?, upiRef?, bankRef? }`.

**Adding a new bank**: write `parseXBank(_ msg:) -> ParsedSMSResult?`, add to `parse(_:)`'s ordered list before generic fallbacks.

### PDF Parsing (`Infrastructure/Parsing/PDFStatementParser.swift`)

Pipeline: PDFKit extraction → multi-line record stitching (date-start detection) → column-scramble bail-out → per-record `parseTransactionLine` → `inferAmountAndType`.

Amount regex uses comma-grouped only (`\d{1,3}(?:,\d{2,3})+`) — never space-grouped to avoid misreads like "14 747.50".

Column-scrambled detection: if PDFKit reads table column-first (HDFC Savings symptom), parsing bails rather than emitting garbage.

### Categorisation (`Infrastructure/Categorization/`)

`CategoryClassifier.classify` 5-step cascade:
1. CC-payment shortcut (avoids salary heuristic on large credits)
2. User rule lookup via `MerchantRuleStore` — confidence 1.0
3. Built-in keyword rules — confidence 0.92
4. Amount heuristic (credits ≥ ₹10K → `salary`) — confidence 0.6
5. Fallback `others` — confidence 0.40 (triggers Review)

`MerchantNormalizer` strips UPI prefixes, VPA (`@*`), trailing ref tokens, corporate suffixes, then checks `aliasMap`. User display-name rules win before any cleanup.

### Bill Cycle (`Infrastructure/BillCycle/BillCycleManager.swift`)

Runs on launch + after each transaction save. For each CC account with `statementDay`/`dueDay`: computes cycle window, sums debits, creates `CardStatement` if missing, schedules notifications. Auto-marks paid when matching `cc_payment` transaction found within ±1% amount.

### Deep Linking (`App/DeepLinkHandler.swift`)

URL scheme: `financetracker://import?sms=<URL-encoded>`. Two-layer dedup: 10s hash window in `DeepLinkHandler` + `rawContent` recency check in `SMSImportView.autoParseAndSave`.

### Quick Review (`Features/Transactions/Components/QuickReviewSheet.swift`)

Snapshots `pendingReviewTransactions` on `init` — parent mutations don't shift indices mid-review. `onConfirm` callback: `(TransactionEntity, newName, newSlug, rememberName, rememberCategory, applyToPast) -> Void`.

## Data Model Notes

- `TransactionEntity.effectiveIntent` — user override wins, then category default.
- `AccountEntity` — `statementDay` + `dueDay` drive CC cycle automation.
- `CategoryEntity` — 26 system categories; each has a `CategoryIntent` mapping to Needs/Wants/Savings (50/30/20).
- SwiftData models mirror entities; all `@Model` properties have property-level defaults (CloudKit-ready).

## Sample Data

Seeded on first launch unless `seedDisabled` UserDefaults flag is set (toggled by Clear All Data). Real card last4s sync via `accountRepo.syncUserCards()` every launch. PDFs in `unlocked/` are gitignored — contain real bank statements.

## Common Extension Points

**New bank SMS parser** → `SMSParser.swift`, then add to ordered list in `parse(_:)`.

**New PDF direction marker** → extend `inferAmountAndType` in `PDFStatementParser.swift`.

**New category** → `CategoryEntity.system` (slug/name/icon/color/sortOrder) + `intent` switch + optional tuple in `CategoryClassifier.merchantRules`.

**New Smart Insight** → `Features/Dashboard/Components/SmartInsightsCard.swift` heuristic engine.
