# FinanceTracker

A personal-use iPhone finance tracker for the Indian market. Built in Swift / SwiftUI for iOS 17+ with SwiftData persistence and no external dependencies.

The goal: every bank transaction gets captured automatically — via SMS, PDF statements, or manual entry — and shows up categorised, linked to the right card, and fed into a 50/30/20 needs/wants/savings view alongside per-goal projections.

## Capabilities

**Transaction capture**
- **SMS** — paste a bank SMS into the app (manual paste OR via the Apple Shortcuts automation that fires on every bank message). Parsed by 7 bank-specific parsers (HDFC Savings debit & credit, HDFC CC, ICICI CC, SBI CC, Federal Bank) with generic fallbacks for Axis / Kotak / Yes Bank / IDFC / IndusInd / RBL.
- **PDF statements** — Tata Neu / Regalia / SBI Cashback / ICICI Sapphiro / Federal Bank PDFs. Multi-line transaction records are stitched back together. HDFC Savings PDFs are column-scrambled by PDFKit and are skipped honestly (user is told).
- **Manual** — standard add-transaction sheet.

**Categorisation**
- 26 system categories (Food, Groceries, Dining, Travel, Shopping, EMI, Rent, Subscriptions, Investments, Gifts, Pets, Donations, CC Payment, etc.).
- Keyword classifier maps merchants to categories (Swiggy → Food, Zerodha → Investments, etc.).
- User-trainable: confirm a category once with the "Remember" toggle on and every future transaction from that merchant auto-categorises. Same toggle remembers display names — `Upi-jay-rent-vpa123` becomes `Rent` in every future import.
- Bulk re-categorisation: saving a rule retroactively updates every past transaction from the same merchant.

**Per-transaction intent (Needs / Wants / Savings)**
- Each category has a default intent.
- Override per-transaction: swipe right on any row for **Need** (green), swipe left for **Want** (amber). Long-press for the full menu including **Saving** and **Clear override**.
- Analytics shows the 50/30/20 breakdown using overrides where set.

**Goals**
- Travel / Home / Vehicle / Education / Emergency / Retirement / Gadget / Wedding / Other.
- Progress ring, target date, monthly contribution required.
- Smart insights surface when a goal is short and recommend the wants category to cut.

**Card statement tracking**
- Configure each credit card's statement day + due day in the account detail.
- `BillCycleManager` auto-creates a `CardStatement` for each completed cycle and schedules daily reminder notifications until paid.
- A matching `cc_payment` transaction (amount within ±1% of total due) auto-marks the statement paid.

**Quick Review**
- Tap the "Need Review" banner on the dashboard or transactions feed.
- Walk through pending reviews one card at a time.
- Editable merchant name, prev/next navigation, separate Remember toggles for name + category + "fix past transactions too".
- Rule-matched rows auto-skip review entirely.

**Security**
- Face ID lock toggle in Settings — re-locks the app on background.
- Local-only persistence (no cloud sync).

**Theme**
- System / Light / Dark picker.

## SMS-to-Transaction Automation

iOS doesn't let third-party apps read SMS. The workaround is an Apple Shortcuts automation backed by a custom **App Intent** (`LogBankSMSIntent`) that runs silently in the background — even when the iPhone is locked.

### One-time Shortcut setup

1. Open **Shortcuts → New Shortcut**.
2. Tap **Add Action** → search for **"Log Bank SMS"** (listed under FinanceTracker).
3. Tap the action → set the **SMS Text** parameter to **Shortcut Input**.
4. Name the shortcut **"Log Bank SMS"** and save.

> **Replacing the old URL-scheme shortcut?** Delete the old 4-step shortcut (Receive → URL Encode → URL → Open URL) and replace it with this single-action version.

### Automation (one per keyword)

Create one automation per keyword — all calling the same "Log Bank SMS" shortcut. False positives from non-bank messages are harmless: the parser returns nil and the SMS is silently dropped.

> **Why not filter by Sender?** Indian bank sender IDs contain hyphens (e.g. `JD-HDFCBK`). iOS Shortcuts strips hyphens when matching sender names, so `JD-HDFCBK` becomes `JDHDFCBK` and never matches. Keyword automations are more reliable.

| Automation | Keyword | Catches |
|---|---|---|
| #1 | `Sent Rs` | HDFC Savings debit |
| #2 | `credited` | HDFC Savings credit |
| #3 | `Txn` | HDFC Tata Neu CC |
| #4 | `Spent` | HDFC Regalia, SBI CC, ICICI CC |
| #5 | `received INR` | Federal Bank credit |
| #6 | `debited` | Generic fallback for other banks |

For each automation:
1. **Shortcuts → Automation → New Automation → Message**.
2. Set **Containing**: enter the keyword from the table above.
3. Set **Run**: **Immediately**.
4. Add action: **Run Shortcut → "Log Bank SMS"** with **Message Content** as input.

### How it works

When a bank SMS arrives (phone locked or unlocked):
1. iOS fires the automation → calls `LogBankSMSIntent` silently in the background.
2. The intent writes the SMS text to a shared App Group queue (no UI shown, no unlock required).
3. Next time you open FinanceTracker, the app drains the queue and saves all pending transactions automatically.

Transactions are deduplicated: the same SMS saved within 2 minutes is skipped.

## Setup

1. Open `FinanceTracker.xcodeproj` in Xcode 15+ (iOS 17 deployment target).
2. Signing & Capabilities — set your Personal Team. No paid Apple Developer Program required for local-only use.
3. Build & run on a physical iPhone (recommended — biometric and notification testing don't work fully on simulator).

### Optional: iCloud sync

Currently disabled by default. To enable:

1. Paid Apple Developer Program account.
2. Xcode → Target FinanceTracker → Signing & Capabilities → + Capability → iCloud → ✓ CloudKit → container `iCloud.com.sovinnour.FinanceTracker`.
3. Change `cloudKitDatabase: .none` to `.automatic` in `FinanceTrackerApp.swift`.

## Architecture

Clean Architecture: `Domain` (value types) → `Data` (SwiftData models + repositories) → `Features` (`@Observable` view models + SwiftUI views). All view models are `@MainActor`. AppContainer owns the model context and exposes typed repositories.

```
FinanceTracker/
├── App/                    – Entry point, DI container, deep-link router, root content view
├── Domain/Entities/        – Value types (TransactionEntity, GoalEntity, CategoryEntity, …)
├── Data/
│   ├── Models/             – SwiftData @Model classes
│   ├── Repositories/       – Type-safe wrappers around ModelContext
│   └── SampleData.swift    – Seed accounts + sample transactions for first launch
├── Infrastructure/
│   ├── Parsing/            – SMSParser, PDFStatementParser, MerchantNormalizer
│   ├── Categorization/     – CategoryClassifier, MerchantRuleStore
│   ├── Notifications/      – Card-due-date + budget reminder scheduler
│   ├── BillCycle/          – BillCycleManager (statement creation + auto-mark-paid)
│   └── Auth/               – BiometricAuthService
├── Features/
│   ├── Dashboard/          – Home tab: summary, insights, top merchants, cards-due
│   ├── Transactions/       – Feed, detail, Quick Review, SMS import, manual add
│   ├── Analytics/          – Trends, category breakdown, 50/30/20 card
│   ├── Budgets/            – Monthly budgets + goals section
│   ├── Goals/              – CRUD + contribution flow
│   ├── Accounts/           – Account detail, cycle-day config
│   ├── Settings/           – Profile, theme, Face ID, PDF import
│   ├── Lock/               – Face ID lock screen
│   └── Onboarding/         – First-launch flow
├── Shared/                 – Reusable views (ToastView, CategoryIconView, …)
└── DesignSystem/           – AppColors, AppFonts, AppSpacing
```

## Bank parsing notes

| Bank | Source | Strategy |
|---|---|---|
| HDFC Savings | SMS | regex on `"Sent Rs.X From HDFC Bank A/C *XXXX To MERCHANT On DD/MM/YY Ref XXX"` |
| HDFC Savings | PDF | **skipped** — PDFKit reads columns top-first, scrambling rows beyond recovery |
| HDFC Tata Neu | SMS | regex on `"Txn Rs.X On HDFC Bank Card XXXX At MERCHANT by UPI XXX On DD-MM"` |
| HDFC Tata Neu | PDF | `+` sign before amount → credit; column-aware parsing |
| HDFC Regalia | SMS | regex on `"Spent Rs.X On HDFC Bank Card XXXX At MERCHANT On YYYY-MM-DD:HH:MM:SS"` |
| HDFC Regalia | PDF | same as Tata Neu (same statement template) |
| ICICI Sapphiro | SMS | regex on `"INR X spent using ICICI Bank Card XX2000 on DD-Mon-YY on MERCHANT"` |
| ICICI Sapphiro | PDF | `CR` suffix → credit; multi-line records stitched |
| SBI Cashback | SMS | regex on `"Rs.X spent on your SBI Credit Card ending XXXX at MERCHANT on DD/MM/YY"` |
| SBI Cashback | PDF | `C` / `D` last character on row determines direction |
| Federal Bank | SMS | regex on `"received INR X in Account XXXXX. … sent by NAME on Month DD, YYYY"` |
| Federal Bank | PDF | column-aware: 3 amounts on row [withdrawal, deposit, balance]; index of non-zero non-balance amount determines direction |

## Apple Shortcuts URL scheme

`financetracker://import?sms=<URL-encoded-SMS-text>`

Opens the app, jumps to the Transactions tab, and triggers the auto-save flow with the supplied SMS. De-duplicated by SMS hash (10-second window) and by `rawContent` match in the last 2 minutes.

## Files of interest for new contributors

| File | What's there |
|---|---|
| `Infrastructure/Parsing/SMSParser.swift` | Bank-specific SMS regex patterns. Add new bank parsers here. |
| `Infrastructure/Parsing/PDFStatementParser.swift` | PDF text extraction, multi-line record stitching, column-aware direction inference. |
| `Infrastructure/Categorization/CategoryClassifier.swift` | Keyword rules. Adding a new merchant → just add a tuple here. |
| `Infrastructure/Categorization/MerchantNormalizer.swift` | Alias map (`SWGY → Swiggy`, `AGODAPANYPTELTD → Agoda`). |
| `Domain/Entities/CategoryEntity.swift` | All 26 system categories + their 50/30/20 intent map. |
| `Features/Dashboard/Components/SmartInsightsCard.swift` | Heuristic recommendations engine. |

See `APP_SUMMARY.md` for an architecture-level summary tailored for AI agents.
