import SwiftUI
import Observation

@Observable
@MainActor
final class BudgetsViewModel {

    // MARK: - State
    var budgets: [BudgetEntity] = []
    var transactions: [TransactionEntity] = []
    var showCreateSheet: Bool = false
    var isLoading: Bool = false

    // MARK: - Dependencies
    private let transactionRepo: TransactionRepositoryImpl
    private let budgetRepo: BudgetRepositoryImpl

    init(transactionRepo: TransactionRepositoryImpl, budgetRepo: BudgetRepositoryImpl) {
        self.transactionRepo = transactionRepo
        self.budgetRepo = budgetRepo
    }

    // MARK: - Computed

    var budgetsWithSpend: [BudgetEntity] {
        budgets.map { budget in
            var updated = budget
            updated.spent = computeSpent(for: budget)
            return updated
        }
        .sorted { $0.progress > $1.progress }
    }

    var totalBudgeted: Decimal {
        budgets.filter(\.isActive).reduce(0) { $0 + $1.amount }
    }

    var totalSpent: Decimal {
        budgetsWithSpend.reduce(0) { $0 + $1.spent }
    }

    var overBudgetCount: Int {
        budgetsWithSpend.filter(\.isOverBudget).count
    }

    var warningCount: Int {
        budgetsWithSpend.filter { $0.isWarning && !$0.isOverBudget }.count
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }

        budgets = budgetRepo.fetchAll()
        transactions = transactionRepo.fetchForMonth(Date())
    }

    // MARK: - Compute Spent

    func computeSpent(for budget: BudgetEntity) -> Decimal {
        let cal = Calendar.current
        let now = Date()

        let startDate: Date
        let endDate: Date

        switch budget.period {
        case .weekly:
            startDate = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            endDate = cal.date(byAdding: .day, value: 6, to: startDate) ?? now
        case .monthly:
            let comps = cal.dateComponents([.year, .month], from: now)
            startDate = cal.date(from: comps) ?? now
            endDate = cal.date(byAdding: DateComponents(month: 1, day: -1), to: startDate) ?? now
        case .annual:
            let comps = cal.dateComponents([.year], from: now)
            startDate = cal.date(from: comps) ?? now
            endDate = cal.date(byAdding: DateComponents(year: 1, day: -1), to: startDate) ?? now
        }

        return transactions
            .filter { txn in
                txn.categorySlug == budget.categorySlug &&
                txn.isDebit &&
                txn.date >= startDate &&
                txn.date <= endDate
            }
            .reduce(0) { $0 + $1.amount }
    }

    // MARK: - CRUD

    func createBudget(categorySlug: String, amount: Decimal, period: BudgetPeriod) {
        let budget = BudgetEntity(
            id: UUID(),
            categorySlug: categorySlug,
            amount: amount,
            period: period,
            startDate: periodStartDate(period),
            isActive: true
        )
        budgetRepo.save(budget)
        budgets.append(budget)
    }

    func deleteBudget(id: UUID) {
        budgetRepo.delete(id: id)
        budgets.removeAll { $0.id == id }
    }

    // MARK: - Helpers

    private func periodStartDate(_ period: BudgetPeriod) -> Date {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .weekly:
            return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        case .monthly:
            return cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        case .annual:
            return cal.date(from: cal.dateComponents([.year], from: now)) ?? now
        }
    }
}
