import Foundation

struct MonthlyAnalysis {
    var month: Date
    var totalIncome: Decimal
    var totalExpenses: Decimal
    var savings: Decimal
    var savingsRate: Double
    var categoryBreakdown: [CategorySpend]
    var topMerchants: [MerchantSpend]
    var subscriptions: [SubscriptionItem]
    var dayWiseSpend: [DaySpend]
    var previousMonthExpenses: Decimal
    var spendChangePercent: Double
}

struct CategorySpend: Identifiable {
    var id: String { categorySlug }
    var categorySlug: String
    var amount: Decimal
    var count: Int
    var percent: Double
}

struct MerchantSpend: Identifiable {
    var id: String { merchantName }
    var merchantName: String
    var amount: Decimal
    var count: Int
    var categorySlug: String
}

struct SubscriptionItem: Identifiable {
    var id: String { merchantName }
    var merchantName: String
    var amount: Decimal
    var categorySlug: String
    var nextDate: Date?
}

struct DaySpend: Identifiable {
    var id: String { date.ISO8601Format() }
    var date: Date
    var amount: Decimal
}
