import SwiftUI
import Observation

@Observable
@MainActor
final class AnalyticsViewModel {

    // MARK: - State
    var selectedMonth: Date = Calendar.current.startOfMonth(for: Date())
    var transactions: [TransactionEntity] = []
    var analysis: MonthlyAnalysis?
    var selectedCategory: String?
    var last6MonthsData: [MonthlyAnalysis] = []
    var isLoading: Bool = false

    // 50/30/20 breakdown for the selected month
    var needsWantsBreakdown: NeedsWantsBreakdown {
        var needs: Decimal = 0
        var wants: Decimal = 0
        var savings: Decimal = 0
        for txn in transactions where txn.isDebit {
            guard let intent = txn.effectiveIntent else { continue }
            switch intent {
            case .need:   needs += txn.amount
            case .want:   wants += txn.amount
            case .saving: savings += txn.amount
            }
        }
        return NeedsWantsBreakdown(needs: needs, wants: wants, savings: savings)
    }

    // MARK: - Dependencies
    private let transactionRepo: TransactionRepositoryImpl
    private let budgetRepo: BudgetRepositoryImpl

    init(transactionRepo: TransactionRepositoryImpl, budgetRepo: BudgetRepositoryImpl) {
        self.transactionRepo = transactionRepo
        self.budgetRepo = budgetRepo
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let all = transactionRepo.fetchAll()
        let monthTxns = transactionRepo.fetchForMonth(selectedMonth)
        transactions = monthTxns

        analysis = computeAnalysisForMonth(selectedMonth, txns: monthTxns, allTxns: all)
        last6MonthsData = computeLast6Months(all)
    }

    func selectMonth(_ date: Date) {
        selectedMonth = Calendar.current.startOfMonth(for: date)
        Task { await load() }
    }

    func selectCategory(_ slug: String?) {
        withAnimation(.springy) {
            selectedCategory = selectedCategory == slug ? nil : slug
        }
    }

    // MARK: - Compute Last 6 Months

    func computeLast6Months(_ allTxns: [TransactionEntity]) -> [MonthlyAnalysis] {
        let cal = Calendar.current
        return (0..<6).reversed().compactMap { offset -> MonthlyAnalysis? in
            guard let month = cal.date(byAdding: .month, value: -offset, to: selectedMonth) else { return nil }
            let start = cal.startOfMonth(for: month)
            let monthTxns = allTxns.filter { cal.isDate($0.date, equalTo: start, toGranularity: .month) }
            return computeAnalysisForMonth(start, txns: monthTxns, allTxns: allTxns)
        }
    }

    // MARK: - Private helpers

    private func computeAnalysisForMonth(_ month: Date, txns: [TransactionEntity], allTxns: [TransactionEntity]) -> MonthlyAnalysis {
        let cal = Calendar.current

        let income: Decimal = txns
            .filter { $0.isCredit && !isTransfer($0.categorySlug) }
            .reduce(0) { $0 + $1.amount }

        let expenses: Decimal = txns
            .filter { $0.isDebit && !isTransfer($0.categorySlug) }
            .reduce(0) { $0 + $1.amount }

        let savings = income - expenses
        let savingsRate: Double = income > 0
            ? Double(truncating: (savings / income * 100) as NSDecimalNumber)
            : 0

        // Category breakdown
        var catMap: [String: (Decimal, Int)] = [:]
        for txn in txns where txn.isDebit && !isTransfer(txn.categorySlug) {
            let cur = catMap[txn.categorySlug] ?? (0, 0)
            catMap[txn.categorySlug] = (cur.0 + txn.amount, cur.1 + 1)
        }

        let catBreakdown = catMap
            .sorted { $0.value.0 > $1.value.0 }
            .prefix(6)
            .map { slug, val -> CategorySpend in
                let pct = expenses > 0 ? Double(truncating: (val.0 / expenses * 100) as NSDecimalNumber) : 0
                return CategorySpend(categorySlug: slug, amount: val.0, count: val.1, percent: pct)
            }

        // Top merchants
        var merchantMap: [String: (Decimal, Int, String)] = [:]
        for txn in txns where txn.isDebit {
            let name = txn.merchantName.isEmpty ? txn.merchantRaw : txn.merchantName
            let cur = merchantMap[name] ?? (0, 0, txn.categorySlug)
            merchantMap[name] = (cur.0 + txn.amount, cur.1 + 1, txn.categorySlug)
        }
        let topMerchants = merchantMap
            .sorted { $0.value.0 > $1.value.0 }
            .prefix(5)
            .map { MerchantSpend(merchantName: $0.key, amount: $0.value.0, count: $0.value.1, categorySlug: $0.value.2) }

        // Subscriptions
        let subs = txns
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
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        for txn in txns where txn.isDebit {
            let key = fmt.string(from: txn.date)
            dayMap[key] = (dayMap[key] ?? 0) + txn.amount
        }

        let startOfMonth = cal.startOfMonth(for: month)
        let daysInMonth = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        var dayWise: [DaySpend] = []
        for day in 0..<daysInMonth {
            if let date = cal.date(byAdding: .day, value: day, to: startOfMonth) {
                let key = fmt.string(from: date)
                dayWise.append(DaySpend(date: date, amount: dayMap[key] ?? 0))
            }
        }

        // Previous month comparison
        let prevMonth = cal.date(byAdding: .month, value: -1, to: month) ?? month
        let prevTxns = allTxns.filter { cal.isDate($0.date, equalTo: cal.startOfMonth(for: prevMonth), toGranularity: .month) }
        let prevExpenses: Decimal = prevTxns
            .filter { $0.isDebit && !isTransfer($0.categorySlug) }
            .reduce(0) { $0 + $1.amount }

        let changePercent: Double = prevExpenses > 0
            ? Double(truncating: ((expenses - prevExpenses) / prevExpenses * 100) as NSDecimalNumber)
            : 0

        return MonthlyAnalysis(
            month: month,
            totalIncome: income,
            totalExpenses: expenses,
            savings: savings,
            savingsRate: savingsRate,
            categoryBreakdown: Array(catBreakdown),
            topMerchants: Array(topMerchants),
            subscriptions: Array(subs),
            dayWiseSpend: dayWise,
            previousMonthExpenses: prevExpenses,
            spendChangePercent: changePercent
        )
    }

    private func isTransfer(_ slug: String) -> Bool {
        ["transfer", "internal-transfer", "credit-card-payment"].contains(slug)
    }

    private func isSubscriptionCategory(_ slug: String) -> Bool {
        ["subscriptions", "entertainment", "streaming", "software"].contains(slug)
    }
}

// MARK: - Calendar helper
private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}
