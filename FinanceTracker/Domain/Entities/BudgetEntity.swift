import Foundation

struct BudgetEntity: Identifiable, Equatable {
    let id: UUID
    var categorySlug: String
    var amount: Decimal
    var period: BudgetPeriod
    var startDate: Date
    var isActive: Bool

    // Computed with actual spend — passed in from analytics
    var spent: Decimal = 0
    var remaining: Decimal { amount - spent }
    var progress: Double {
        guard amount > 0 else { return 0 }
        return min(1.0, Double(truncating: (spent / amount) as NSDecimalNumber))
    }
    var isOverBudget: Bool { spent > amount }
    var isWarning: Bool { progress > 0.8 && !isOverBudget }

    init(
        id: UUID = UUID(),
        categorySlug: String,
        amount: Decimal,
        period: BudgetPeriod = .monthly,
        startDate: Date = Date(),
        isActive: Bool = true
    ) {
        self.id = id
        self.categorySlug = categorySlug
        self.amount = amount
        self.period = period
        self.startDate = startDate
        self.isActive = isActive
    }
}

enum BudgetPeriod: String, Codable, CaseIterable {
    case weekly   = "weekly"
    case monthly  = "monthly"
    case annual   = "annual"

    var displayName: String {
        switch self {
        case .weekly:  return "Weekly"
        case .monthly: return "Monthly"
        case .annual:  return "Annual"
        }
    }
}
