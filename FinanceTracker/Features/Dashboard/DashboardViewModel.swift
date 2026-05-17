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
    var pendingReviewTransactions: [TransactionEntity] = []
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

    func confirmReview(transaction: TransactionEntity, newName: String?, newSlug: String, rememberName: Bool, rememberCategory: Bool, applyToPast: Bool = false) {
        var updated = transaction
        if let n = newName, !n.isEmpty { updated.merchantName = n }
        updated.categorySlug = newSlug
        updated.isConfirmed = true
        updated.confidence = 1.0
        transactionRepo.update(updated)
        pendingReviewTransactions.removeAll { $0.id == transaction.id }
        pendingReviewCount = pendingReviewTransactions.count

        if rememberName || rememberCategory {
            MerchantRuleStore.shared.saveRule(
                merchant: transaction.merchantRaw.isEmpty ? transaction.merchantName : transaction.merchantRaw,
                categorySlug: rememberCategory ? newSlug : nil,
                displayName: rememberName ? newName : nil
            )
        }

        if applyToPast && rememberCategory {
            let key = transaction.merchantRaw.isEmpty ? transaction.merchantName : transaction.merchantRaw
            transactionRepo.bulkRecategorize(merchantRaw: key, merchantNameKey: transaction.merchantName, newSlug: newSlug)
        }
    }

    func deleteTransaction(_ id: UUID) {
        transactionRepo.delete(id: id)
        pendingReviewTransactions.removeAll { $0.id == id }
        pendingReviewCount = pendingReviewTransactions.count
    }

    // MARK: - Computed

    var unreadInsightCount: Int { insights.filter { !$0.isRead }.count }
    var visibleInsights: [InsightEntity] { insights.filter { !$0.isRead } }

    // MARK: - Insight dismissal (persisted via UserDefaults)

    private static let dismissedInsightsKey = "dismissedInsightIDs"

    static func persistedDismissedInsightIDs() -> Set<UUID> {
        let raw = UserDefaults.standard.array(forKey: dismissedInsightsKey) as? [String] ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    private static func setPersistedDismissedInsightIDs(_ ids: Set<UUID>) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: dismissedInsightsKey)
    }

    func dismissInsight(_ id: UUID) {
        var ids = Self.persistedDismissedInsightIDs()
        ids.insert(id)
        Self.setPersistedDismissedInsightIDs(ids)
        if let idx = insights.firstIndex(where: { $0.id == id }) {
            insights[idx].isRead = true
        }
    }

    // MARK: - Public Methods

    func load() async {
        isLoading = true
        defer { isLoading = false }

        accounts = accountRepo?.fetchAll() ?? []
        upcomingStatements = cardStatementRepo?.fetchUnpaid() ?? []

        let monthTxns = transactionRepo.fetchForMonth(selectedMonth)
        let prevMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        let prevMonthTxns = transactionRepo.fetchForMonth(prevMonth)
        let pending = transactionRepo.fetchPendingReview()

        transactions = monthTxns
        pendingReviewTransactions = pending
        pendingReviewCount = pending.count

        let computed = computeAnalysis(monthTxns, prevMonthTransactions: prevMonthTxns)
        analysis = computed
        insights = generateInsights(from: computed)

        // Smart insights — uses goals + monthly income/spend AND trailing history
        // for anomaly detection / recurring-transaction discovery.
        let goals = goalRepo?.fetchAll() ?? []
        let monthlyIncome = monthTxns.filter(\.isCredit).reduce(Decimal(0)) { $0 + $1.amount }
        let cal = Calendar.current
        let sixMonthsAgo = cal.date(byAdding: .month, value: -6, to: selectedMonth) ?? Date.distantPast
        let history = transactionRepo.fetchAll(from: sixMonthsAgo, to: selectedMonth)
        smartInsights = SmartInsightsEngine.generate(
            transactions: monthTxns,
            historicalTransactions: history,
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

    // txns is already month-scoped; prevMonthTransactions is pre-fetched from the prior month.
    func computeAnalysis(_ txns: [TransactionEntity], prevMonthTransactions: [TransactionEntity] = []) -> MonthlyAnalysis {
        let cal = Calendar.current

        let income: Decimal = txns
            .filter { $0.isCredit && !isTransferCategory($0.categorySlug) }
            .reduce(0) { $0 + $1.amount }

        let expenses: Decimal = txns
            .filter { $0.isDebit && !isTransferCategory($0.categorySlug) }
            .reduce(0) { $0 + $1.amount }

        let savings = income - expenses
        let savingsRate: Double = income > 0
            ? Double(truncating: (savings / income * 100) as NSDecimalNumber)
            : 0

        // Category Breakdown (top 6)
        var categoryMap: [String: (Decimal, Int)] = [:]
        for txn in txns where txn.isDebit && !isTransferCategory(txn.categorySlug) {
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
        for txn in txns where txn.isDebit {
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
        let subscriptions = txns
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

        // Day-wise spend (cached formatter — no allocation per call)
        var dayMap: [String: Decimal] = [:]
        for txn in txns where txn.isDebit {
            let key = Self.dayFormatter.string(from: txn.date)
            dayMap[key] = (dayMap[key] ?? 0) + txn.amount
        }
        let range = monthDateRange(for: selectedMonth)
        var dayWise: [DaySpend] = []
        var cursor = range.start
        while cursor <= range.end {
            let key = Self.dayFormatter.string(from: cursor)
            dayWise.append(DaySpend(date: cursor, amount: dayMap[key] ?? 0))
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }

        // Previous month expenses — use pre-fetched data, no re-filtering by date needed
        let prevExpenses: Decimal = prevMonthTransactions
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

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Insight Generation

    func generateInsights(from analysis: MonthlyAnalysis) -> [InsightEntity] {
        var result: [InsightEntity] = []
        let cal = Calendar.current
        let mk = "\(Int(selectedMonth.timeIntervalSince1970))"

        // Persisted-across-launches set of insights the user has dismissed.
        // Union with in-memory state in case generation runs mid-session.
        let persistedRead = Self.persistedDismissedInsightIDs()
        let memoryRead = Set(insights.filter(\.isRead).map(\.id))
        let alreadyRead = persistedRead.union(memoryRead)
        func makeInsight(key: String, type: InsightType, title: String, body: String,
                         amount: Decimal? = nil, categorySlug: String? = nil) -> InsightEntity {
            let id = stableInsightID("\(key)-\(mk)")
            return InsightEntity(id: id, type: type, title: title, body: body,
                                 amount: amount, categorySlug: categorySlug,
                                 date: Date(), isRead: alreadyRead.contains(id))
        }

        // 1. Savings insight
        if analysis.savings > 0 {
            result.append(makeInsight(
                key: "savings-pos",
                type: .positive,
                title: "Great savings this month!",
                body: String(format: "You saved %.0f%% of your income — ₹%@ kept safe.", analysis.savingsRate, analysis.savings.compactString),
                amount: analysis.savings
            ))
        } else if analysis.savings < 0 {
            result.append(makeInsight(
                key: "savings-neg",
                type: .warning,
                title: "Spending exceeds income",
                body: "You spent ₹\((-analysis.savings).compactString) more than you earned this month.",
                amount: -analysis.savings
            ))
        }

        // 2. Top category spend warning
        if let topCat = analysis.categoryBreakdown.first {
            let cat = CategoryEntity.find(slug: topCat.categorySlug)
            let changeAbs = analysis.spendChangePercent
            if changeAbs > 20 {
                result.append(makeInsight(
                    key: "top-cat-warn",
                    type: .warning,
                    title: "\(cat.name) spend up \(Int(abs(changeAbs)))%",
                    body: "Your top category this month is \(cat.name) at ₹\(topCat.amount.compactString). That's significantly higher than last month.",
                    amount: topCat.amount,
                    categorySlug: topCat.categorySlug
                ))
            } else {
                result.append(makeInsight(
                    key: "top-cat-neutral",
                    type: .neutral,
                    title: "Top spend: \(cat.name)",
                    body: "\(cat.name) accounts for \(Int(topCat.percent))% of your expenses at ₹\(topCat.amount.compactString) this month.",
                    amount: topCat.amount,
                    categorySlug: topCat.categorySlug
                ))
            }
        }

        // 3. Subscription cost tip
        if !analysis.subscriptions.isEmpty {
            let total = analysis.subscriptions.reduce(Decimal(0)) { $0 + $1.amount }
            result.append(makeInsight(
                key: "subscriptions",
                type: .tip,
                title: "Subscriptions cost ₹\(total.compactString)/mo",
                body: "You have \(analysis.subscriptions.count) active subscription\(analysis.subscriptions.count == 1 ? "" : "s"). Review if all are still needed.",
                amount: total,
                categorySlug: "subscriptions"
            ))
        }

        // 4. Pending review
        if pendingReviewCount > 0 {
            result.append(makeInsight(
                key: "pending-review",
                type: .neutral,
                title: "\(pendingReviewCount) transaction\(pendingReviewCount == 1 ? "" : "s") need review",
                body: "Some transactions were auto-categorized with low confidence. Tap to confirm or correct them."
            ))
        }

        // 5. Largest merchant
        if let topMerchant = analysis.topMerchants.first {
            result.append(makeInsight(
                key: "top-merchant",
                type: .neutral,
                title: "Largest spend: \(topMerchant.merchantName)",
                body: "You made \(topMerchant.count) payment\(topMerchant.count == 1 ? "" : "s") totaling ₹\(topMerchant.amount.compactString) at \(topMerchant.merchantName).",
                amount: topMerchant.amount,
                categorySlug: topMerchant.categorySlug
            ))
        }

        // 6. Month over month comparison
        if analysis.previousMonthExpenses > 0 {
            let change = analysis.spendChangePercent
            if abs(change) > 5 {
                let direction = change > 0 ? "up" : "down"
                result.append(makeInsight(
                    key: "mom-change",
                    type: change > 0 ? .warning : .positive,
                    title: "Spending \(direction) \(Int(abs(change)))% vs last month",
                    body: "Last month: ₹\(analysis.previousMonthExpenses.compactString) | This month: ₹\(analysis.totalExpenses.compactString)",
                    amount: analysis.totalExpenses
                ))
            }
        }

        // 7. Daily average tip
        let daysInMonth = cal.range(of: .day, in: .month, for: selectedMonth)?.count ?? 30
        if analysis.totalExpenses > 0 {
            let avg = analysis.totalExpenses / Decimal(daysInMonth)
            result.append(makeInsight(
                key: "daily-avg",
                type: .tip,
                title: "Daily average: ₹\(avg.compactString)",
                body: "You're spending about ₹\(avg.compactString) per day this month across \(transactions.count) transactions.",
                amount: avg
            ))
        }

        return Array(result.prefix(7))
    }

    /// Produces a deterministic UUID from a string key using FNV-1a so insight IDs
    /// survive reloads and isRead state can be preserved across refreshes.
    private func stableInsightID(_ key: String) -> UUID {
        var h1: UInt64 = 14695981039346656037
        var h2: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            h1 = (h1 ^ UInt64(byte)) &* 1099511628211
        }
        for byte in key.utf8.reversed() {
            h2 = (h2 ^ UInt64(byte)) &* 0x100000001b3
        }
        let uuidString = String(format: "%08X-%04X-%04X-%04X-%012X",
            UInt32(h1 >> 32),
            UInt16((h1 >> 16) & 0xFFFF),
            UInt16(0x4000 | (h1 & 0x0FFF)),
            UInt16(0x8000 | (h2 >> 48 & 0x3FFF)),
            h2 & 0x0000FFFFFFFFFFFF)
        return UUID(uuidString: uuidString) ?? UUID()
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
