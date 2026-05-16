import SwiftUI
import Observation

@Observable
@MainActor
final class DashboardViewModel {

    // MARK: - Published State
    var selectedMonth: Date = Calendar.current.startOfMonth(for: Date())
    var transactions: [TransactionEntity] = []
    var analysis: MonthlyAnalysis?
    var pendingReviewCount: Int = 0
    var accounts: [AccountEntity] = []
    var insights: [InsightEntity] = []
    var isLoading: Bool = false
    var upcomingStatements: [CardStatementEntity] = []
    var smartInsights: [SmartInsight] = []

    // MARK: - Dependencies
    private let transactionRepo: TransactionRepositoryImpl
    private let budgetRepo: BudgetRepositoryImpl
    private let accountRepo: AccountRepositoryImpl?
    private let cardStatementRepo: CardStatementRepositoryImpl?
    private let goalRepo: GoalRepositoryImpl?

    init(transactionRepo: TransactionRepositoryImpl,
         budgetRepo: BudgetRepositoryImpl,
         accountRepo: AccountRepositoryImpl? = nil,
         cardStatementRepo: CardStatementRepositoryImpl? = nil,
         goalRepo: GoalRepositoryImpl? = nil) {
        self.transactionRepo   = transactionRepo
        self.budgetRepo        = budgetRepo
        self.accountRepo       = accountRepo
        self.cardStatementRepo = cardStatementRepo
        self.goalRepo          = goalRepo
    }

    func markStatementPaid(_ id: UUID) {
        cardStatementRepo?.markPaid(id)
        NotificationManager.shared.cancelReminders(for: id)
        upcomingStatements.removeAll { $0.id == id }
    }

    // MARK: - Public Methods

    func load() async {
        isLoading = true
        defer { isLoading = false }

        accounts = accountRepo?.fetchAll() ?? []
        upcomingStatements = cardStatementRepo?.fetchUnpaid() ?? []

        let all = transactionRepo.fetchAll()
        let monthTxns = transactionRepo.fetchForMonth(selectedMonth)
        let pending = transactionRepo.fetchPendingReview()

        transactions = monthTxns
        pendingReviewCount = pending.count

        let computed = computeAnalysis(monthTxns, allTransactions: all)
        analysis = computed
        insights = generateInsights(from: computed)

        // Smart insights — uses goals + monthly income/spend
        let goals = goalRepo?.fetchAll() ?? []
        let monthlyIncome = monthTxns.filter(\.isCredit).reduce(Decimal(0)) { $0 + $1.amount }
        smartInsights = SmartInsightsEngine.generate(
            transactions: monthTxns,
            goals: goals,
            monthlyIncome: monthlyIncome
        )
    }

    func selectMonth(_ date: Date) {
        selectedMonth = Calendar.current.startOfMonth(for: date)
        Task { await load() }
    }

    func refreshData() {
        Task { await load() }
    }

    // MARK: - Analysis Computation

    func computeAnalysis(_ txns: [TransactionEntity], allTransactions: [TransactionEntity] = []) -> MonthlyAnalysis {
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month], from: selectedMonth)
        let monthTxns = txns.filter {
            let c = cal.dateComponents([.year, .month], from: $0.date)
            return c.year == components.year && c.month == components.month
        }

        // Previous month
        let prevMonth = cal.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        let prevComponents = cal.dateComponents([.year, .month], from: prevMonth)
        let prevTxns = allTransactions.filter {
            let c = cal.dateComponents([.year, .month], from: $0.date)
            return c.year == prevComponents.year && c.month == prevComponents.month
        }

        // Income & Expenses
        let income: Decimal = monthTxns
            .filter { $0.isCredit && !isTransferCategory($0.categorySlug) }
            .reduce(0) { $0 + $1.amount }

        let expenses: Decimal = monthTxns
            .filter { $0.isDebit && !isTransferCategory($0.categorySlug) }
            .reduce(0) { $0 + $1.amount }

        let savings = income - expenses
        let savingsRate: Double = income > 0
            ? Double(truncating: (savings / income * 100) as NSDecimalNumber)
            : 0

        // Category Breakdown (top 6)
        var categoryMap: [String: (Decimal, Int)] = [:]
        for txn in monthTxns where txn.isDebit && !isTransferCategory(txn.categorySlug) {
            let existing = categoryMap[txn.categorySlug] ?? (0, 0)
            categoryMap[txn.categorySlug] = (existing.0 + txn.amount, existing.1 + 1)
        }

        let totalExpensesDouble = Double(truncating: expenses as NSDecimalNumber)
        let sortedCategories = categoryMap
            .sorted { $0.value.0 > $1.value.0 }
            .prefix(6)
            .map { slug, value in
                let pct = totalExpensesDouble > 0
                    ? Double(truncating: (value.0 / expenses * 100) as NSDecimalNumber)
                    : 0
                return CategorySpend(categorySlug: slug, amount: value.0, count: value.1, percent: pct)
            }

        // Top Merchants (top 5)
        var merchantMap: [String: (Decimal, Int, String)] = [:]
        for txn in monthTxns where txn.isDebit {
            let key = txn.merchantName.isEmpty ? txn.merchantRaw : txn.merchantName
            let existing = merchantMap[key] ?? (0, 0, txn.categorySlug)
            merchantMap[key] = (existing.0 + txn.amount, existing.1 + 1, txn.categorySlug)
        }
        let topMerchants = merchantMap
            .sorted { $0.value.0 > $1.value.0 }
            .prefix(5)
            .map { name, val in
                MerchantSpend(merchantName: name, amount: val.0, count: val.1, categorySlug: val.2)
            }

        // Subscriptions
        let subscriptions = monthTxns
            .filter { $0.isRecurring && isSubscriptionCategory($0.categorySlug) }
            .reduce(into: [String: SubscriptionItem]()) { dict, txn in
                let key = txn.merchantName.isEmpty ? txn.merchantRaw : txn.merchantName
                if dict[key] == nil {
                    dict[key] = SubscriptionItem(
                        merchantName: key,
                        amount: txn.amount,
                        categorySlug: txn.categorySlug,
                        nextDate: cal.date(byAdding: .month, value: 1, to: txn.date)
                    )
                }
            }
            .values
            .sorted { $0.amount > $1.amount }

        // Day-wise spend
        var dayMap: [String: Decimal] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        for txn in monthTxns where txn.isDebit {
            let key = formatter.string(from: txn.date)
            dayMap[key] = (dayMap[key] ?? 0) + txn.amount
        }
        let range = monthDateRange(for: selectedMonth)
        var dayWise: [DaySpend] = []
        var cursor = range.start
        while cursor <= range.end {
            let key = formatter.string(from: cursor)
            dayWise.append(DaySpend(date: cursor, amount: dayMap[key] ?? 0))
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }

        // Previous month expenses
        let prevExpenses: Decimal = prevTxns
            .filter { $0.isDebit && !isTransferCategory($0.categorySlug) }
            .reduce(0) { $0 + $1.amount }

        let changePercent: Double = prevExpenses > 0
            ? Double(truncating: ((expenses - prevExpenses) / prevExpenses * 100) as NSDecimalNumber)
            : 0

        return MonthlyAnalysis(
            month: selectedMonth,
            totalIncome: income,
            totalExpenses: expenses,
            savings: savings,
            savingsRate: savingsRate,
            categoryBreakdown: Array(sortedCategories),
            topMerchants: Array(topMerchants),
            subscriptions: Array(subscriptions),
            dayWiseSpend: dayWise,
            previousMonthExpenses: prevExpenses,
            spendChangePercent: changePercent
        )
    }

    // MARK: - Insight Generation

    func generateInsights(from analysis: MonthlyAnalysis) -> [InsightEntity] {
        var result: [InsightEntity] = []
        let cal = Calendar.current

        // 1. Savings insight
        if analysis.savings > 0 {
            result.append(InsightEntity(
                id: UUID(),
                type: .positive,
                title: "Great savings this month!",
                body: String(format: "You saved %.0f%% of your income — ₹%@ kept safe.", analysis.savingsRate, analysis.savings.compactString),
                amount: analysis.savings,
                categorySlug: nil,
                date: Date(),
                isRead: false
            ))
        } else if analysis.savings < 0 {
            result.append(InsightEntity(
                id: UUID(),
                type: .warning,
                title: "Spending exceeds income",
                body: "You spent ₹\((-analysis.savings).compactString) more than you earned this month.",
                amount: -analysis.savings,
                categorySlug: nil,
                date: Date(),
                isRead: false
            ))
        }

        // 2. Top category spend warning
        if let topCat = analysis.categoryBreakdown.first {
            let cat = CategoryEntity.find(slug: topCat.categorySlug)
            let changeAbs = analysis.spendChangePercent
            if changeAbs > 20 {
                result.append(InsightEntity(
                    id: UUID(),
                    type: .warning,
                    title: "\(cat.name) spend up \(Int(abs(changeAbs)))%",
                    body: "Your top category this month is \(cat.name) at ₹\(topCat.amount.compactString). That's significantly higher than last month.",
                    amount: topCat.amount,
                    categorySlug: topCat.categorySlug,
                    date: Date(),
                    isRead: false
                ))
            } else {
                result.append(InsightEntity(
                    id: UUID(),
                    type: .neutral,
                    title: "Top spend: \(cat.name)",
                    body: "\(cat.name) accounts for \(Int(topCat.percent))% of your expenses at ₹\(topCat.amount.compactString) this month.",
                    amount: topCat.amount,
                    categorySlug: topCat.categorySlug,
                    date: Date(),
                    isRead: false
                ))
            }
        }

        // 3. Subscription cost tip
        if !analysis.subscriptions.isEmpty {
            let total = analysis.subscriptions.reduce(Decimal(0)) { $0 + $1.amount }
            result.append(InsightEntity(
                id: UUID(),
                type: .tip,
                title: "Subscriptions cost ₹\(total.compactString)/mo",
                body: "You have \(analysis.subscriptions.count) active subscription\(analysis.subscriptions.count == 1 ? "" : "s"). Review if all are still needed.",
                amount: total,
                categorySlug: "subscriptions",
                date: Date(),
                isRead: false
            ))
        }

        // 4. Pending review
        if pendingReviewCount > 0 {
            result.append(InsightEntity(
                id: UUID(),
                type: .neutral,
                title: "\(pendingReviewCount) transaction\(pendingReviewCount == 1 ? "" : "s") need review",
                body: "Some transactions were auto-categorized with low confidence. Tap to confirm or correct them.",
                amount: nil,
                categorySlug: nil,
                date: Date(),
                isRead: false
            ))
        }

        // 5. Largest merchant
        if let topMerchant = analysis.topMerchants.first {
            result.append(InsightEntity(
                id: UUID(),
                type: .neutral,
                title: "Largest spend: \(topMerchant.merchantName)",
                body: "You made \(topMerchant.count) payment\(topMerchant.count == 1 ? "" : "s") totaling ₹\(topMerchant.amount.compactString) at \(topMerchant.merchantName).",
                amount: topMerchant.amount,
                categorySlug: topMerchant.categorySlug,
                date: Date(),
                isRead: false
            ))
        }

        // 6. Month over month comparison
        if analysis.previousMonthExpenses > 0 {
            let change = analysis.spendChangePercent
            if abs(change) > 5 {
                let direction = change > 0 ? "up" : "down"
                let insightType: InsightType = change > 0 ? .warning : .positive
                result.append(InsightEntity(
                    id: UUID(),
                    type: insightType,
                    title: "Spending \(direction) \(Int(abs(change)))% vs last month",
                    body: "Last month: ₹\(analysis.previousMonthExpenses.compactString) | This month: ₹\(analysis.totalExpenses.compactString)",
                    amount: analysis.totalExpenses,
                    categorySlug: nil,
                    date: Date(),
                    isRead: false
                ))
            }
        }

        // 7. Daily average tip
        let daysInMonth = cal.range(of: .day, in: .month, for: selectedMonth)?.count ?? 30
        if analysis.totalExpenses > 0 {
            let avg = analysis.totalExpenses / Decimal(daysInMonth)
            result.append(InsightEntity(
                id: UUID(),
                type: .tip,
                title: "Daily average: ₹\(avg.compactString)",
                body: "You're spending about ₹\(avg.compactString) per day this month across \(transactions.count) transactions.",
                amount: avg,
                categorySlug: nil,
                date: Date(),
                isRead: false
            ))
        }

        return Array(result.prefix(7))
    }

    // MARK: - Helpers

    private func isTransferCategory(_ slug: String) -> Bool {
        ["transfer", "internal-transfer", "credit-card-payment"].contains(slug)
    }

    private func isSubscriptionCategory(_ slug: String) -> Bool {
        ["subscriptions", "entertainment", "streaming", "software"].contains(slug)
    }

    private func monthDateRange(for date: Date) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        let start = cal.date(from: comps) ?? date
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? date
        return (start, end)
    }
}

// MARK: - Calendar Helper
private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}
