import Foundation
import SwiftData

@MainActor
class BudgetRepositoryImpl {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() -> [BudgetEntity] {
        let descriptor = FetchDescriptor<BudgetModel>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.categorySlug)]
        )
        return (try? modelContext.fetch(descriptor))?.map { $0.toEntity() } ?? []
    }

    func save(_ entity: BudgetEntity) {
        let model = BudgetModel(
            id: entity.id,
            categorySlug: entity.categorySlug,
            amount: Double(truncating: entity.amount as NSDecimalNumber),
            periodRaw: entity.period.rawValue,
            startDate: entity.startDate,
            isActive: entity.isActive
        )
        modelContext.insert(model)
        try? modelContext.save()
    }

    func delete(id: UUID) {
        let descriptor = FetchDescriptor<BudgetModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(model)
        try? modelContext.save()
    }

    func deleteAll() {
        guard let models = try? modelContext.fetch(FetchDescriptor<BudgetModel>()) else { return }
        for model in models {
            modelContext.delete(model)
        }
        try? modelContext.save()
    }
}
