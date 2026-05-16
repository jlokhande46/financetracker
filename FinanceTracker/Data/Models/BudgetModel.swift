import Foundation
import SwiftData

@Model
final class BudgetModel {
    @Attribute(.unique) var id: UUID
    var categorySlug: String
    var amount: Double
    var periodRaw: String
    var startDate: Date
    var isActive: Bool

    var period: BudgetPeriod {
        get { BudgetPeriod(rawValue: periodRaw) ?? .monthly }
        set { periodRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        categorySlug: String,
        amount: Double,
        periodRaw: String = "monthly",
        startDate: Date = Date(),
        isActive: Bool = true
    ) {
        self.id = id
        self.categorySlug = categorySlug
        self.amount = amount
        self.periodRaw = periodRaw
        self.startDate = startDate
        self.isActive = isActive
    }

    func toEntity() -> BudgetEntity {
        BudgetEntity(
            id: id,
            categorySlug: categorySlug,
            amount: Decimal(amount),
            period: period,
            startDate: startDate,
            isActive: isActive
        )
    }
}
