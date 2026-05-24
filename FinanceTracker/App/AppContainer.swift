import SwiftUI
import SwiftData

// MARK: - AppContainer

@MainActor
class AppContainer {
    let transactionRepo: TransactionRepositoryImpl
    let accountRepo: AccountRepositoryImpl
    let budgetRepo: BudgetRepositoryImpl
    let cardStatementRepo: CardStatementRepositoryImpl
    let goalRepo: GoalRepositoryImpl
    let recurringBillRepo: RecurringBillRepositoryImpl
    let investmentRepo: InvestmentHoldingRepositoryImpl
    let billCycleManager: BillCycleManager
    let salaryWatcher: SalaryWatcher

    init(modelContext: ModelContext) {
        self.transactionRepo     = TransactionRepositoryImpl(modelContext: modelContext)
        self.accountRepo         = AccountRepositoryImpl(modelContext: modelContext)
        self.budgetRepo          = BudgetRepositoryImpl(modelContext: modelContext)
        self.cardStatementRepo   = CardStatementRepositoryImpl(modelContext: modelContext)
        self.goalRepo            = GoalRepositoryImpl(modelContext: modelContext)
        self.recurringBillRepo   = RecurringBillRepositoryImpl(modelContext: modelContext)
        self.investmentRepo      = InvestmentHoldingRepositoryImpl(modelContext: modelContext)
        self.billCycleManager    = BillCycleManager(
            accountRepo: accountRepo,
            statementRepo: cardStatementRepo,
            transactionRepo: transactionRepo
        )
        self.salaryWatcher       = SalaryWatcher(
            transactionRepo: transactionRepo,
            recurringBillRepo: recurringBillRepo
        )

        // Always sync user's real cards so account auto-linking works
        // regardless of whether sample data was cleared.
        accountRepo.syncUserCards()

        // Seed sample transactions on first launch only.
        let seedDisabled = UserDefaults.standard.bool(forKey: "seedDisabled")
        if !seedDisabled {
            transactionRepo.seedSampleData()
        }
        // Seed the user's five common recurring bills if they have none yet.
        // Skipped silently on subsequent launches (count > 0 guard inside).
        recurringBillRepo.seedDefaultsIfNeeded()

        // Run the bill-cycle sweep so any overdue statements are created and any
        // already-paid ones get marked.
        billCycleManager.runDailySweep()
        // Check whether a recent salary should kick off bill reminders for any
        // cycle still unpaid.
        salaryWatcher.handleStateChange()
        // (Re)schedule the daily rotating finance tip — one pending repeating
        // notification that fires every day at 9:30 AM.
        NotificationManager.shared.scheduleFinanceTip()
    }

    /// Drains any SMS texts queued by `LogBankSMSIntent` (the App Intent that
    /// fires from Shortcuts automations even while the phone is locked) and
    /// saves them as transactions. Called every time the app becomes active.
    ///
    /// Duplicates are suppressed: an SMS already saved within the last 2 minutes
    /// is skipped (same dedup window as the URL-scheme deep-link path).
    ///
    /// Each queued item carries its `enqueuedAt` timestamp from when the
    /// Shortcut/URL fired — the saved transaction's `date` is derived from
    /// it whenever the parsed SMS lacks a time component, and `createdAt`
    /// is always set to it. This preserves the *sequence* of multiple SMS
    /// processed in one batch (e.g. user opens the app after lunch and
    /// 3 queued bank texts drain — they line up in arrival order instead
    /// of all sharing the moment-of-app-open timestamp).
    func processPendingSMS() {
        let items = PendingSMSStore.drainItems()
        guard !items.isEmpty else { return }

        let existing = transactionRepo.fetchAll()
        let now = Date()
        var savedAny = false

        // Items in arrival order — use index to stagger sub-second offsets
        // when multiple items share the same enqueuedAt timestamp (rare).
        for (index, item) in items.enumerated() {
            let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Skip if the exact same SMS was saved in the last 2 minutes.
            let isDuplicate = existing.contains { txn in
                txn.rawContent == trimmed && abs(now.timeIntervalSince(txn.createdAt)) < 120
            }
            guard !isDuplicate else {
                SMSAuditStore.record(.savedDeduped, text: trimmed, at: now,
                                     detail: "Identical rawContent saved within last 2 minutes.")
                continue
            }

            guard let result = SMSParser.shared.parse(trimmed) else {
                SMSAuditStore.record(.parseFailed, text: trimmed, at: now,
                                     detail: "Main-app parse retry also returned nil.")
                continue
            }

            let merchant = MerchantNormalizer.shared.normalize(result.merchantRaw)
            let classification = CategoryClassifier.shared.classify(
                merchantName: merchant,
                amount: result.amount,
                type: result.type,
                rawContent: trimmed
            )
            // Account auto-link uses the same 3-tier matcher as the SMSImportView
            // path (last4 → bank-keyword-to-last4 → single-account-of-bank).
            let autoAccount = SMSImportView.linkAccount(
                for: result,
                rawText: trimmed,
                accounts: accountRepo.fetchAll()
            )

            // Bump createdAt by the queue index so a batch arriving with the
            // same enqueuedAt (back-to-back Shortcut fires) still sorts in
            // arrival order on createdAt rather than collapsing onto one
            // instant.
            let createdAt = item.enqueuedAt.addingTimeInterval(TimeInterval(index) * 0.001)
            let transactionDate = resolveTransactionDate(
                parsed: result.date,
                enqueuedAt: createdAt
            )

            let entity = TransactionEntity(
                amount: result.amount,
                type: result.type,
                merchantRaw: result.merchantRaw,
                merchantName: merchant.isEmpty ? result.merchantRaw : merchant,
                categorySlug: classification.categorySlug,
                date: transactionDate,
                source: .sms,
                confidence: classification.confidence,
                isConfirmed: true,
                accountId: autoAccount?.id,
                upiRef: result.upiRef,
                bankRef: result.bankRef,
                rawContent: trimmed,
                createdAt: createdAt
            )
            transactionRepo.save(entity)
            // Arrival notification has already fired (from LogBankSMSIntent
            // or DeepLinkHandler). Only re-notify if the saved row needs
            // review — surfaces low-confidence categorisations the user
            // would otherwise miss in the feed.
            NotificationManager.shared.fireTransactionNeedsReviewAlert(for: entity)
            SMSAuditStore.record(
                .savedAsTransaction, text: trimmed, at: createdAt,
                detail: String(
                    format: "%@ ₹%@ · %@ · conf %.0f%%",
                    entity.isCredit ? "+" : "-",
                    "\(entity.amount)",
                    entity.merchantName.isEmpty ? entity.merchantRaw : entity.merchantName,
                    entity.confidence * 100
                )
            )
            savedAny = true
        }

        if savedAny {
            billCycleManager.handleTransactionChange()
            // A newly-saved salary credit should kick off bill reminders; a
            // newly-saved expense should refresh the unpaid set in case the
            // user paid a bill via this SMS.
            salaryWatcher.handleStateChange()
        }
    }

    /// Build the persisted `date` for an SMS-derived transaction so the row
    /// sorts correctly in the feed.
    ///
    /// - If the SMS parser captured a full datetime (e.g. Federal Bank Sent,
    ///   HDFC CC Spent), we use it as-is — it's the most accurate.
    /// - If the SMS captured only a date (most banks), we keep the parsed
    ///   day-of-month but graft the receipt time-of-day on top, so two SMS
    ///   arriving 30s apart on the same calendar date don't collapse onto
    ///   midnight (which would lose sequence).
    /// - If parsing produced no date at all, fall back to the queue
    ///   timestamp.
    private func resolveTransactionDate(parsed: Date?, enqueuedAt: Date) -> Date {
        guard let parsed else { return enqueuedAt }
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute, .second], from: parsed)
        let hasTime = (comps.hour ?? 0) != 0 || (comps.minute ?? 0) != 0 || (comps.second ?? 0) != 0
        if hasTime { return parsed }
        // Date-only SMS: combine parsed Y/M/D with the queue's H/M/S so the
        // row keeps its real calendar date but still has a meaningful time
        // of day for sequencing.
        var ymd = cal.dateComponents([.year, .month, .day], from: parsed)
        let hms = cal.dateComponents([.hour, .minute, .second], from: enqueuedAt)
        ymd.hour = hms.hour
        ymd.minute = hms.minute
        ymd.second = hms.second
        return cal.date(from: ymd) ?? enqueuedAt
    }

    /// Permanently delete every transaction, account, budget, merchant rule, and statement.
    /// Also flips a flag so sample transactions won't re-seed on next launch.
    /// Accounts are immediately re-synced so the user isn't left with an empty
    /// account picker — they represent the user's real cards, not test data.
    func clearAllData() {
        transactionRepo.deleteAll()
        accountRepo.deleteAll()
        budgetRepo.deleteAll()
        cardStatementRepo.deleteAll()
        goalRepo.deleteAll()
        recurringBillRepo.deleteAll()
        investmentRepo.deleteAll()
        MerchantRuleStore.shared.deleteAll()
        NotificationManager.shared.cancelAll()
        SalaryWatcher.resetSalaryAnnouncementDedup()
        UserDefaults.standard.set(true, forKey: "seedDisabled")
        // Re-seed user's real cards + recurring bills immediately. clearAllData
        // should reset the app's learned state, NOT remove the standing setup.
        accountRepo.syncUserCards()
        recurringBillRepo.seedDefaultsIfNeeded()
    }
}

// MARK: - EnvironmentKey

struct AppContainerKey: EnvironmentKey {
    static let defaultValue: AppContainer? = nil
}

extension EnvironmentValues {
    var appContainer: AppContainer? {
        get { self[AppContainerKey.self] }
        set { self[AppContainerKey.self] = newValue }
    }
}
