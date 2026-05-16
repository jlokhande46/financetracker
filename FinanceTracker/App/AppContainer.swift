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

    init(modelContext: ModelContext) {
        self.transactionRepo     = TransactionRepositoryImpl(modelContext: modelContext)
        self.accountRepo         = AccountRepositoryImpl(modelContext: modelContext)
        self.budgetRepo          = BudgetRepositoryImpl(modelContext: modelContext)
        self.cardStatementRepo   = CardStatementRepositoryImpl(modelContext: modelContext)
        self.goalRepo            = GoalRepositoryImpl(modelContext: modelContext)

        // Always sync user's real cards so account auto-linking works
        // regardless of whether sample data was cleared.
        accountRepo.syncUserCards()

        // Seed sample transactions on first launch only.
        let seedDisabled = UserDefaults.standard.bool(forKey: "seedDisabled")
        if !seedDisabled {
            transactionRepo.seedSampleData()
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
