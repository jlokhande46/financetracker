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
    let billCycleManager: BillCycleManager

    init(modelContext: ModelContext) {
        self.transactionRepo     = TransactionRepositoryImpl(modelContext: modelContext)
        self.accountRepo         = AccountRepositoryImpl(modelContext: modelContext)
        self.budgetRepo          = BudgetRepositoryImpl(modelContext: modelContext)
        self.cardStatementRepo   = CardStatementRepositoryImpl(modelContext: modelContext)
        self.goalRepo            = GoalRepositoryImpl(modelContext: modelContext)
        self.billCycleManager    = BillCycleManager(
            accountRepo: accountRepo,
            statementRepo: cardStatementRepo,
            transactionRepo: transactionRepo
        )

        // Always sync user's real cards so account auto-linking works
        // regardless of whether sample data was cleared.
        accountRepo.syncUserCards()

        // Seed sample transactions on first launch only.
        let seedDisabled = UserDefaults.standard.bool(forKey: "seedDisabled")
        if !seedDisabled {
            transactionRepo.seedSampleData()
        }

        // Run the bill-cycle sweep so any overdue statements are created and any
        // already-paid ones get marked.
        billCycleManager.runDailySweep()
    }

    /// Drains any SMS texts queued by `LogBankSMSIntent` (the App Intent that
    /// fires from Shortcuts automations even while the phone is locked) and
    /// saves them as transactions. Called every time the app becomes active.
    ///
    /// Duplicates are suppressed: an SMS already saved within the last 2 minutes
    /// is skipped (same dedup window as the URL-scheme deep-link path).
    func processPendingSMS() {
        let pending = PendingSMSStore.drainQueue()
        guard !pending.isEmpty else { return }

        let existing = transactionRepo.fetchAll()
        let now = Date()
        var savedAny = false

        for text in pending {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Skip if the exact same SMS was saved in the last 2 minutes.
            let isDuplicate = existing.contains { txn in
                txn.rawContent == trimmed && abs(now.timeIntervalSince(txn.createdAt)) < 120
            }
            guard !isDuplicate else { continue }

            guard let result = SMSParser.shared.parse(trimmed) else { continue }

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

            let entity = TransactionEntity(
                amount: result.amount,
                type: result.type,
                merchantRaw: result.merchantRaw,
                merchantName: merchant.isEmpty ? result.merchantRaw : merchant,
                categorySlug: classification.categorySlug,
                date: result.date ?? now,
                source: .sms,
                confidence: classification.confidence,
                isConfirmed: true,
                accountId: autoAccount?.id,
                upiRef: result.upiRef,
                bankRef: result.bankRef,
                rawContent: trimmed
            )
            transactionRepo.save(entity)
            savedAny = true
        }

        if savedAny {
            billCycleManager.handleTransactionChange()
        }
    }

    /// Permanently delete every transaction, account, budget, merchant rule, and statement.
    /// Also flips a flag so sample data won't re-seed on next launch.
    func clearAllData() {
        transactionRepo.deleteAll()
        accountRepo.deleteAll()
        budgetRepo.deleteAll()
        cardStatementRepo.deleteAll()
        goalRepo.deleteAll()
        MerchantRuleStore.shared.deleteAll()
        NotificationManager.shared.cancelAll()
        UserDefaults.standard.set(true, forKey: "seedDisabled")
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
