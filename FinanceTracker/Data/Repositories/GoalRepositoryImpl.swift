import Foundation
import SwiftData

@MainActor
final class GoalRepositoryImpl {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) { self.modelContext = modelContext }

    func fetchAll() -> [GoalEntity] {
        let descriptor = FetchDescriptor<GoalModel>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? modelContext.fetch(descriptor))?.map { $0.toEntity() } ?? []
    }

    func save(_ entity: GoalEntity) {
        let existing = (try? modelContext.fetch(FetchDescriptor<GoalModel>()))?.first { $0.id == entity.id }
        if let model = existing {
            model.name = entity.name
            model.typeRaw = entity.type.rawValue
            model.targetAmountDouble = Double(truncating: entity.targetAmount as NSDecimalNumber)
            model.currentAmountDouble = Double(truncating: entity.currentAmount as NSDecimalNumber)
            model.targetDate = entity.targetDate
            model.notes = entity.notes
            model.isCompleted = entity.isCompleted
        } else {
            let model = GoalModel(
                id: entity.id,
                name: entity.name,
                typeRaw: entity.type.rawValue,
                targetAmountDouble: Double(truncating: entity.targetAmount as NSDecimalNumber),
                currentAmountDouble: Double(truncating: entity.currentAmount as NSDecimalNumber),
                targetDate: entity.targetDate,
                notes: entity.notes,
                isCompleted: entity.isCompleted,
                createdAt: entity.createdAt
            )
            modelContext.insert(model)
        }
        try? modelContext.save()
    }

    func addContribution(goalId: UUID, amount: Decimal) {
        guard let model = (try? modelContext.fetch(FetchDescriptor<GoalModel>()))?.first(where: { $0.id == goalId }) else { return }
        model.currentAmountDouble += Double(truncating: amount as NSDecimalNumber)
        if model.currentAmountDouble >= model.targetAmountDouble {
            model.isCompleted = true
        }
        try? modelContext.save()
    }

    func delete(_ id: UUID) {
        guard let model = (try? modelContext.fetch(FetchDescriptor<GoalModel>()))?.first(where: { $0.id == id }) else { return }
        modelContext.delete(model)
        try? modelContext.save()
    }

    func deleteAll() {
        guard let models = try? modelContext.fetch(FetchDescriptor<GoalModel>()) else { return }
        for m in models { modelContext.delete(m) }
        try? modelContext.save()
    }
}
