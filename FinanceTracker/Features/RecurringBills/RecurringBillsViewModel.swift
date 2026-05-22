import SwiftUI
import Observation

/// View model for the Recurring Bills section. Owns the live bill list and
/// the candidate-transaction selection logic used by `MarkBillPaidSheet`.
@Observable
@MainActor
final class RecurringBillsViewModel {

    var bills: [RecurringBillEntity] = []
    /// Refreshed alongside `bills` — most-recent salary credit in the last
    /// 30 days, if any. Drives the "Salary received" tag in the section header.
    var recentSalary: TransactionEntity? = nil

    // Sheet plumbing
    var showAddEditSheet: Bool = false
    var editingBill: RecurringBillEntity? = nil
    var billToMarkPaid: RecurringBillEntity? = nil

    // MARK: - Dependencies
    private let billRepo: RecurringBillRepositoryImpl
    private let transactionRepo: TransactionRepositoryImpl
    private let salaryWatcher: SalaryWatcher

    init(
        billRepo: RecurringBillRepositoryImpl,
        transactionRepo: TransactionRepositoryImpl,
        salaryWatcher: SalaryWatcher
    ) {
        self.billRepo = billRepo
        self.transactionRepo = transactionRepo
        self.salaryWatcher = salaryWatcher
    }

    // MARK: - Computed

    var unpaidBills: [RecurringBillEntity] {
        bills.filter { $0.isActive && $0.isDueThisCycle }
    }

    var paidBills: [RecurringBillEntity] {
        bills.filter { $0.isActive && !$0.isDueThisCycle }
    }

    var unpaidCount: Int { unpaidBills.count }
    var hasSalary: Bool { recentSalary != nil }

    /// Sort: overdue first, then by days until due ascending, then by name.
    var sortedBills: [RecurringBillEntity] {
        bills.filter { $0.isActive }.sorted { a, b in
            if a.isDueThisCycle != b.isDueThisCycle { return a.isDueThisCycle }
            if a.daysUntilDue != b.daysUntilDue { return a.daysUntilDue < b.daysUntilDue }
            return a.name < b.name
        }
    }

    // MARK: - Lifecycle

    func load() {
        bills = billRepo.fetchAll()
        recentSalary = salaryWatcher.recentSalary()
    }

    // MARK: - Mutations

    func save(_ entity: RecurringBillEntity) {
        billRepo.save(entity)
        load()
        salaryWatcher.handleStateChange()
    }

    func delete(_ id: UUID) {
        billRepo.delete(id)
        NotificationManager.shared.cancelBillReminders(billId: id)
        load()
        salaryWatcher.handleStateChange()
    }

    func markPaid(bill: RecurringBillEntity, transactionId: UUID?) {
        billRepo.markPaid(billId: bill.id, transactionId: transactionId)
        NotificationManager.shared.cancelBillReminders(billId: bill.id)
        load()
        salaryWatcher.handleStateChange()
    }

    func resetLastPaid(billId: UUID) {
        billRepo.resetLastPaid(billId: billId)
        load()
        salaryWatcher.handleStateChange()
    }

    // MARK: - Mark-Paid transaction picker

    /// Candidate transactions the user might have used to pay a given bill.
    /// Filtered to debits within the last 14 days, prioritising rows whose
    /// category matches the bill type's `likelyCategorySlugs` and whose
    /// amount is within ±25% of the bill's expected amount (if set).
    ///
    /// Returned newest first. The picker also offers a "None of these" cell
    /// for paid-outside-app cases — the bill is still marked paid, just
    /// without a linked transaction id.
    func paymentCandidates(for bill: RecurringBillEntity, lookbackDays: Int = 14) -> [TransactionEntity] {
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? Date()
        let pool = transactionRepo.fetchAll(from: from).filter { $0.isDebit }

        // Score = lower is better. Distance from expected amount (when known)
        // + category mismatch penalty.
        let categoryHits = Set(bill.type.likelyCategorySlugs)
        let scored = pool.map { txn -> (TransactionEntity, Double) in
            var score: Double = 0
            if let expected = bill.amount {
                let expD = NSDecimalNumber(decimal: expected).doubleValue
                let actD = NSDecimalNumber(decimal: txn.amount).doubleValue
                if expD > 0 {
                    let pctOff = abs(actD - expD) / expD
                    score += pctOff * 100
                }
            }
            if !categoryHits.isEmpty, !categoryHits.contains(txn.categorySlug) {
                score += 50
            }
            // Prefer recent — but only as a tiebreaker.
            score += Double(cal.dateComponents([.day], from: txn.date, to: Date()).day ?? 0) * 0.5
            return (txn, score)
        }
        return scored.sorted { $0.1 < $1.1 }.map { $0.0 }
    }
}
