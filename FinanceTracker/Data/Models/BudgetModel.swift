import Foundation
import SwiftData

@Model
final class BudgetModel {
    @Attribute(.unique) var id: UUID = UUID()
    var categorySlug: String = "others"
    var amount: Double = 0
    var periodRaw: String = "monthly"
    var startDate: Date = Date()
    var isActive: Bool = true

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
