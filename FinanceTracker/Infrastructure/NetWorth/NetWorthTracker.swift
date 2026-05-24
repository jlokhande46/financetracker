import Foundation

/// Computes and snapshots the user's net worth:
///   Assets  = Savings/Current account balances + Investment holdings
///   Liabilities = Credit card outstanding balances
///   Net Worth = Assets − Liabilities
///
/// A monthly snapshot is stored in UserDefaults so the Analytics tab can
/// show a 12-month net-worth trend without requiring a separate time-series
/// model. Updated lazily: the first `compute()` each calendar month appends
/// the previous month's value to the history.
@MainActor
final class NetWorthTracker {

    private let accountRepo: AccountRepositoryImpl
    private let investmentRepo: InvestmentHoldingRepositoryImpl

    private static let historyKey = "netWorthHistory"

    init(accountRepo: AccountRepositoryImpl,
         investmentRepo: InvestmentHoldingRepositoryImpl) {
        self.accountRepo = accountRepo
        self.investmentRepo = investmentRepo
    }

    struct Snapshot: Equatable {
        let savings: Decimal
        let investments: Decimal
        let liabilities: Decimal
        var totalAssets: Decimal { savings + investments }
        var netWorth: Decimal { totalAssets - liabilities }
        var investmentReturns: Decimal
    }

    struct MonthPoint: Codable, Identifiable {
        var id: String { month }
        let month: String   // "2026-05"
        let value: Double
    }

    /// Live computation from current account + investment state.
    func compute() -> Snapshot {
        let accounts = accountRepo.fetchAll()
        let savingsBalance = accounts
            .filter { $0.type != .credit && $0.isActive }
            .reduce(Decimal(0)) { $0 + $1.balance }
        let ccOutstanding = accounts
            .filter { $0.type == .credit && $0.isActive }
            .reduce(Decimal(0)) { $0 + $1.balance }
        let investmentValue = investmentRepo.totalValue()
        let investedCost = investmentRepo.totalInvested()

        let snapshot = Snapshot(
            savings: savingsBalance,
            investments: investmentValue,
            liabilities: ccOutstanding,
            investmentReturns: investmentValue - investedCost
        )

        recordMonthlySnapshot(snapshot)
        return snapshot
    }

    /// Last 12 months of net-worth values for the trend chart.
    func monthlyHistory() -> [MonthPoint] {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              let points = try? JSONDecoder().decode([MonthPoint].self, from: data)
        else { return [] }
        return Array(points.suffix(12))
    }

    // MARK: - Private

    private func recordMonthlySnapshot(_ snapshot: Snapshot) {
        let monthKey = currentMonthKey()
        var history = fullHistory()
        if let idx = history.firstIndex(where: { $0.month == monthKey }) {
            history[idx] = MonthPoint(month: monthKey, value: NSDecimalNumber(decimal: snapshot.netWorth).doubleValue)
        } else {
            history.append(MonthPoint(month: monthKey, value: NSDecimalNumber(decimal: snapshot.netWorth).doubleValue))
        }
        // Keep last 24 months max.
        if history.count > 24 { history = Array(history.suffix(24)) }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    private func fullHistory() -> [MonthPoint] {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              let points = try? JSONDecoder().decode([MonthPoint].self, from: data)
        else { return [] }
        return points
    }

    private func currentMonthKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }

    static func clearHistory() {
        UserDefaults.standard.removeObject(forKey: historyKey)
    }
}
