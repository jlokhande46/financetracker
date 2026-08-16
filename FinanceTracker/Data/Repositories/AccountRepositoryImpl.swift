import Foundation
import SwiftData

@MainActor
class AccountRepositoryImpl {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() -> [AccountEntity] {
        let descriptor = FetchDescriptor<AccountModel>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? modelContext.fetch(descriptor))?.map { $0.toEntity() } ?? []
    }

    func save(_ entity: AccountEntity) {
        let model = AccountModel(
            id: entity.id,
            name: entity.name,
            bankName: entity.bankName,
            typeRaw: entity.type.rawValue,
            last4: entity.last4,
            balance: Double(truncating: entity.balance as NSDecimalNumber),
            openingBalance: Double(truncating: entity.openingBalance as NSDecimalNumber),
            // Mark as already-seeded only when the caller supplied a real
            // opening balance, so `migrateOpeningBalancesIfNeeded` doesn't
            // clobber it. Seeded sample accounts pass 0 here and get their
            // static `balance` folded in by that migration instead.
            didSeedOpeningBalance: entity.openingBalance != 0,
            creditLimit: entity.creditLimit.map { Double(truncating: $0 as NSDecimalNumber) },
            colorHex: entity.colorHex,
            isActive: entity.isActive,
            statementDay: entity.statementDay,
            dueDay: entity.dueDay,
            createdAt: entity.createdAt
        )
        modelContext.insert(model)
        try? modelContext.save()
    }

    // MARK: - Derived balances

    /// Recompute every account's `balance` from its `openingBalance` plus the
    /// transactions linked to it.
    ///
    /// Balances were previously write-once seed values — nothing in the app
    /// ever updated `balance`, so account chips, credit-utilisation bars and
    /// the Net Worth card all reported whatever `SampleData` happened to seed,
    /// no matter what the user actually spent.
    ///
    /// Sign convention differs by account type:
    ///   - deposit accounts (savings / current / wallet / investment) go UP on
    ///     credits and DOWN on debits.
    ///   - credit cards track OUTSTANDING, so purchases (debits) increase it
    ///     and payments (credits) reduce it.
    ///
    /// Transactions with no `accountId` are ignored — they can't be attributed.
    func recalculateBalances(from transactions: [TransactionEntity]) {
        guard let models = try? modelContext.fetch(FetchDescriptor<AccountModel>()) else { return }

        var netByAccount: [UUID: (credits: Decimal, debits: Decimal)] = [:]
        for txn in transactions {
            guard let accountId = txn.accountId else { continue }
            var entry = netByAccount[accountId] ?? (0, 0)
            if txn.isCredit { entry.credits += txn.amount } else { entry.debits += txn.amount }
            netByAccount[accountId] = entry
        }

        var changed = false
        for model in models {
            let net = netByAccount[model.id] ?? (Decimal(0), Decimal(0))
            let opening = Decimal(model.openingBalance)
            let derived: Decimal = (model.type == .credit)
                ? opening + net.debits - net.credits
                : opening + net.credits - net.debits
            let derivedDouble = Double(truncating: derived as NSDecimalNumber)
            if model.balance != derivedDouble {
                model.balance = derivedDouble
                changed = true
            }
        }
        if changed { try? modelContext.save() }
    }

    /// Fold the legacy static `balance` into `openingBalance` once, so existing
    /// installs keep the figure they were already showing as their starting
    /// point rather than snapping to a transaction-only total.
    func migrateOpeningBalancesIfNeeded() {
        guard let models = try? modelContext.fetch(FetchDescriptor<AccountModel>()) else { return }
        var changed = false
        for model in models where !model.didSeedOpeningBalance {
            model.openingBalance = model.balance
            model.didSeedOpeningBalance = true
            changed = true
        }
        if changed { try? modelContext.save() }
    }

    /// Set the user-supplied starting balance for an account. The derived
    /// `balance` is refreshed by the caller's next `recalculateBalances`.
    func updateOpeningBalance(id: UUID, openingBalance: Decimal) {
        guard let model = (try? modelContext.fetch(FetchDescriptor<AccountModel>()))?
                .first(where: { $0.id == id }) else { return }
        model.openingBalance = Double(truncating: openingBalance as NSDecimalNumber)
        model.didSeedOpeningBalance = true
        try? modelContext.save()
    }

    /// Update just the bill-cycle days for an existing account.
    func updateCycleDays(id: UUID, statementDay: Int?, dueDay: Int?) {
        guard let model = (try? modelContext.fetch(FetchDescriptor<AccountModel>()))?.first(where: { $0.id == id }) else { return }
        model.statementDay = statementDay
        model.dueDay = dueDay
        try? modelContext.save()
    }

    func deleteAll() {
        guard let models = try? modelContext.fetch(FetchDescriptor<AccountModel>()) else { return }
        for model in models {
            modelContext.delete(model)
        }
        try? modelContext.save()
    }

    func seedSampleData() {
        let count = (try? modelContext.fetch(FetchDescriptor<AccountModel>()).count) ?? 0
        guard count == 0 else { return }
        for account in SampleData.accounts { save(account) }
    }

    /// Always called at launch — ensures every real card exists in the DB
    /// with the correct last4, even after a clear-data reset or first install.
    func syncUserCards() {
        let existing = (try? modelContext.fetch(FetchDescriptor<AccountModel>())) ?? []

        var changed = false

        // Remove stale dummy placeholder accounts (old seeded data with fake last4s)
        let dummyLast4s: Set<String> = ["4521", "7892"]
        for model in existing where model.last4.map({ dummyLast4s.contains($0) }) == true {
            modelContext.delete(model)
            changed = true
        }

        // Ensure every real card exists
        let freshModels = (try? modelContext.fetch(FetchDescriptor<AccountModel>())) ?? []
        let freshLast4s = Set(freshModels.compactMap { $0.last4 })
        for account in SampleData.accounts where account.last4 != nil && !freshLast4s.contains(account.last4!) {
            save(account)
            changed = true
        }

        // Backfill statement/due days on any existing card that's missing them.
        // The sample data is the source of truth for the user's real cycle days
        // (HDFC 14/30, ICICI 16/30, SBI 7/21). We only backfill — never overwrite —
        // so a user who customised days in EditCycleSheet keeps their choice.
        let sampleByLast4 = Dictionary(uniqueKeysWithValues:
            SampleData.accounts.compactMap { acc -> (String, AccountEntity)? in
                guard let l4 = acc.last4 else { return nil }
                return (l4, acc)
            }
        )
        let postSyncModels = (try? modelContext.fetch(FetchDescriptor<AccountModel>())) ?? []
        for model in postSyncModels {
            guard let last4 = model.last4, let sample = sampleByLast4[last4] else { continue }
            if model.statementDay == nil, let day = sample.statementDay {
                model.statementDay = day
                changed = true
            }
            if model.dueDay == nil, let day = sample.dueDay {
                model.dueDay = day
                changed = true
            }
        }

        if changed { try? modelContext.save() }
    }
}
