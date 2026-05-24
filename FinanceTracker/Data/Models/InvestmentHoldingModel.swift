import Foundation
import SwiftData

@Model
final class InvestmentHoldingModel {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var typeRaw: String = "mf"
    var currentValueDouble: Double = 0
    var investedAmountDouble: Double = 0
    var lastUpdated: Date = Date()
    var notes: String?
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        typeRaw: String = "mf",
        currentValueDouble: Double,
        investedAmountDouble: Double = 0,
        lastUpdated: Date = Date(),
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.typeRaw = typeRaw
        self.currentValueDouble = currentValueDouble
        self.investedAmountDouble = investedAmountDouble
        self.lastUpdated = lastUpdated
        self.notes = notes
        self.createdAt = createdAt
    }

    func toEntity() -> InvestmentHoldingEntity {
        InvestmentHoldingEntity(
            id: id,
            name: name,
            type: InvestmentType(rawValue: typeRaw) ?? .other,
            currentValue: Decimal(currentValueDouble),
            investedAmount: Decimal(investedAmountDouble),
            lastUpdated: lastUpdated,
            notes: notes,
            createdAt: createdAt
        )
    }
}
