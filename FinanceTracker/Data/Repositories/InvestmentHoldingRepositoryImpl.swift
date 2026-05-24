import Foundation
import SwiftData

@MainActor
final class InvestmentHoldingRepositoryImpl {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() -> [InvestmentHoldingEntity] {
        let descriptor = FetchDescriptor<InvestmentHoldingModel>(
            sortBy: [SortDescriptor(\.currentValueDouble, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor))?.map { $0.toEntity() } ?? []
    }

    func save(_ entity: InvestmentHoldingEntity) {
        let existing = (try? modelContext.fetch(FetchDescriptor<InvestmentHoldingModel>()))?
            .first { $0.id == entity.id }
        if let model = existing {
            model.name = entity.name
            model.typeRaw = entity.type.rawValue
            model.currentValueDouble = Double(truncating: entity.currentValue as NSDecimalNumber)
            model.investedAmountDouble = Double(truncating: entity.investedAmount as NSDecimalNumber)
            model.lastUpdated = entity.lastUpdated
            model.notes = entity.notes
        } else {
            let model = InvestmentHoldingModel(
                id: entity.id,
                name: entity.name,
                typeRaw: entity.type.rawValue,
                currentValueDouble: Double(truncating: entity.currentValue as NSDecimalNumber),
                investedAmountDouble: Double(truncating: entity.investedAmount as NSDecimalNumber),
                lastUpdated: entity.lastUpdated,
                notes: entity.notes,
                createdAt: entity.createdAt
            )
            modelContext.insert(model)
        }
        try? modelContext.save()
    }

    func delete(_ id: UUID) {
        guard let model = (try? modelContext.fetch(FetchDescriptor<InvestmentHoldingModel>()))?
                .first(where: { $0.id == id }) else { return }
        modelContext.delete(model)
        try? modelContext.save()
    }

    func deleteAll() {
        guard let models = try? modelContext.fetch(FetchDescriptor<InvestmentHoldingModel>()) else { return }
        for m in models { modelContext.delete(m) }
        try? modelContext.save()
    }

    /// Total current value across all holdings.
    func totalValue() -> Decimal {
        fetchAll().reduce(Decimal(0)) { $0 + $1.currentValue }
    }

    /// Total invested (cost basis) across all holdings.
    func totalInvested() -> Decimal {
        fetchAll().reduce(Decimal(0)) { $0 + $1.investedAmount }
    }
}
