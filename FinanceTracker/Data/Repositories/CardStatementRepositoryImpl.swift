import Foundation
import SwiftData

@MainActor
final class CardStatementRepositoryImpl {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() -> [CardStatementEntity] {
        let descriptor = FetchDescriptor<CardStatementModel>(
            sortBy: [SortDescriptor(\.dueDate)]
        )
        return (try? modelContext.fetch(descriptor))?.map { $0.toEntity() } ?? []
    }

    func fetchUnpaid() -> [CardStatementEntity] {
        fetchAll().filter { !$0.isPaid }
    }

    func save(_ entity: CardStatementEntity) {
        // Upsert: replace existing record for the same account + dueDate
        let existing = (try? modelContext.fetch(FetchDescriptor<CardStatementModel>()))?.first {
            $0.accountId == entity.accountId && Calendar.current.isDate($0.dueDate, inSameDayAs: entity.dueDate)
        }
        if let model = existing {
            model.totalDueDouble = Double(truncating: entity.totalDue as NSDecimalNumber)
            model.minimumDueDouble = entity.minimumDue.map { Double(truncating: $0 as NSDecimalNumber) }
            model.statementDate = entity.statementDate
            model.isPaid = entity.isPaid
            model.paidDate = entity.paidDate
        } else {
            let model = CardStatementModel(
                id: entity.id,
                accountId: entity.accountId,
                accountName: entity.accountName,
                accountLast4: entity.accountLast4,
                accountColorHex: entity.accountColorHex,
                statementDate: entity.statementDate,
                dueDate: entity.dueDate,
                totalDueDouble: Double(truncating: entity.totalDue as NSDecimalNumber),
                minimumDueDouble: entity.minimumDue.map { Double(truncating: $0 as NSDecimalNumber) },
                isPaid: entity.isPaid,
                paidDate: entity.paidDate,
                importedAt: entity.importedAt
            )
            modelContext.insert(model)
        }
        try? modelContext.save()
    }

    func markPaid(_ id: UUID) {
        guard let model = (try? modelContext.fetch(FetchDescriptor<CardStatementModel>()))?.first(where: { $0.id == id }) else { return }
        model.isPaid = true
        model.paidDate = Date()
        try? modelContext.save()
    }

    func delete(_ id: UUID) {
        guard let model = (try? modelContext.fetch(FetchDescriptor<CardStatementModel>()))?.first(where: { $0.id == id }) else { return }
        modelContext.delete(model)
        try? modelContext.save()
    }

    func deleteAll() {
        guard let models = try? modelContext.fetch(FetchDescriptor<CardStatementModel>()) else { return }
        for m in models { modelContext.delete(m) }
        try? modelContext.save()
    }
}
