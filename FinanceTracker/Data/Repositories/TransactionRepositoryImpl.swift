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
        var predicates: [Predicate<TransactionModel>] = [
            #Predicate { !$0.isDeleted && !$0.isHidden }
        ]
        if let start = startDate {
            predicates.append(#Predicate { $0.date >= start })
        }
        if let end = endDate {
            predicates.append(#Predicate { $0.date <= end })
        }
        descriptor.predicate = predicates.count == 1 ? predicates[0] : #Predicate {
            !$0.isDeleted && !$0.isHidden
        }
        do {
            let models = try modelContext.fetch(descriptor)
            return models.map { $0.toEntity() }
        } catch {
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
        try? modelContext.save()
    }

    func update(_ entity: TransactionEntity) {
        let id = entity.id
        let descriptor = FetchDescriptor<TransactionModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = try? modelContext.fetch(descriptor).first else { return }
        model.merchantName = entity.merchantName
        model.categorySlug = entity.categorySlug
        model.isConfirmed = entity.isConfirmed
        model.notes = entity.notes
        model.tags = entity.tags
        model.isRecurring = entity.isRecurring
        model.updatedAt = Date()
        try? modelContext.save()
    }

    func delete(id: UUID) {
        let descriptor = FetchDescriptor<TransactionModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = try? modelContext.fetch(descriptor).first else { return }
        model.isDeleted = true
        try? modelContext.save()
    }

    func saveBulk(_ entities: [TransactionEntity]) {
        for entity in entities {
            modelContext.insert(TransactionModel.from(entity: entity))
        }
        try? modelContext.save()
    }

    func deleteAll() {
        guard let models = try? modelContext.fetch(FetchDescriptor<TransactionModel>()) else { return }
        for model in models {
            modelContext.delete(model)
        }
        try? modelContext.save()
    }

    func seedSampleData() {
        let count = (try? modelContext.fetch(FetchDescriptor<TransactionModel>()).count) ?? 0
        guard count == 0 else { return }

        let samples = SampleData.transactions
        for entity in samples {
            modelContext.insert(TransactionModel.from(entity: entity))
        }
        try? modelContext.save()
    }
}
