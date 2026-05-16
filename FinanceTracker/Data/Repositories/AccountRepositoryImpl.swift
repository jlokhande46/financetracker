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
        let existingLast4s = Set(existing.compactMap { $0.last4 })

        var changed = false

        // Remove stale dummy placeholder accounts (old seeded data with fake last4s)
        let dummyLast4s: Set<String> = ["4521", "7892"]
        for model in existing where model.last4.map({ dummyLast4s.contains($0) }) == true {
            modelContext.delete(model)
            changed = true
        }

        // Ensure every real card exists
        let freshLast4s = Set((try? modelContext.fetch(FetchDescriptor<AccountModel>()).compactMap { $0.last4 }) ?? [])
        for account in SampleData.accounts where account.last4 != nil && !freshLast4s.contains(account.last4!) {
            save(account)
            changed = true
        }

        if changed { try? modelContext.save() }
    }
}
