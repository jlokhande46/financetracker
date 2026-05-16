import Foundation
import SwiftData

@MainActor
class TransactionRepositoryImpl {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll(from startDate: Date? = nil, to endDate: Date? = nil) -> [TransactionEntity] {
        var descriptor = FetchDescriptor<TransactionModel>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        // #Predicate doesn't support dynamic composition, so branch explicitly.
        if let start = startDate, let end = endDate {
            descriptor.predicate = #Predicate<TransactionModel> { m in
                !m.isDeleted && !m.isHidden && m.date >= start && m.date <= end
            }
        } else if let start = startDate {
            descriptor.predicate = #Predicate<TransactionModel> { m in
                !m.isDeleted && !m.isHidden && m.date >= start
            }
        } else if let end = endDate {
            descriptor.predicate = #Predicate<TransactionModel> { m in
                !m.isDeleted && !m.isHidden && m.date <= end
            }
        } else {
            descriptor.predicate = #Predicate<TransactionModel> { m in
                !m.isDeleted && !m.isHidden
            }
        }
        do {
            let models = try modelContext.fetch(descriptor)
            return models.map { $0.toEntity() }
        } catch {
            assertionFailure("Failed to fetch transactions: \(error)")
            return []
        }
    }

    func fetchForMonth(_ date: Date) -> [TransactionEntity] {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let start = calendar.date(from: comps),
              let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start)
        else { return [] }
        return fetchAll(from: start, to: end)
    }

    func fetchPendingReview() -> [TransactionEntity] {
        let descriptor = FetchDescriptor<TransactionModel>(
            predicate: #Predicate { !$0.isConfirmed && $0.confidence < 0.85 && !$0.isDeleted },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor))?.map { $0.toEntity() } ?? []
    }

    func save(_ entity: TransactionEntity) {
        let model = TransactionModel.from(entity: entity)
        modelContext.insert(model)
        persistChanges()
    }

    func update(_ entity: TransactionEntity) {
        let id = entity.id
        let descriptor = FetchDescriptor<TransactionModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = (try? modelContext.fetch(descriptor))?.first else { return }
        model.amount = NSDecimalNumber(decimal: entity.amount).doubleValue
        model.typeRaw = entity.type.rawValue
        model.merchantRaw = entity.merchantRaw
        model.merchantName = entity.merchantName
        model.categorySlug = entity.categorySlug
        model.subcategorySlug = entity.subcategorySlug
        model.date = entity.date
        model.sourceRaw = entity.source.rawValue
        model.confidence = entity.confidence
        model.isConfirmed = entity.isConfirmed
        model.isRecurring = entity.isRecurring
        model.isSplit = entity.isSplit
        model.parentId = entity.parentId
        model.tags = entity.tags
        model.notes = entity.notes
        model.receiptURL = entity.receiptURL
        model.upiRef = entity.upiRef
        model.bankRef = entity.bankRef
        model.updatedAt = Date()
        persistChanges()
    }

    func delete(id: UUID) {
        let descriptor = FetchDescriptor<TransactionModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = (try? modelContext.fetch(descriptor))?.first else { return }
        model.isDeleted = true
        persistChanges()
    }

    func saveBulk(_ entities: [TransactionEntity]) {
        for entity in entities {
            modelContext.insert(TransactionModel.from(entity: entity))
        }
        persistChanges()
    }

    func deleteAll() {
        guard let models = try? modelContext.fetch(FetchDescriptor<TransactionModel>()) else { return }
        for model in models { modelContext.delete(model) }
        persistChanges()
    }

    func seedSampleData() {
        let count = (try? modelContext.fetch(FetchDescriptor<TransactionModel>()).count) ?? 0
        guard count == 0 else { return }
        for entity in SampleData.transactions {
            modelContext.insert(TransactionModel.from(entity: entity))
        }
        persistChanges()
    }

    private func persistChanges() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("SwiftData save failed: \(error)")
        }
    }
}
