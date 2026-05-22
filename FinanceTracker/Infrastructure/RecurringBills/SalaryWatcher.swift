import Foundation

/// Watches the transaction stream for salary credits and, when one lands,
/// kicks off the recurring-bill reminder schedule for any bill still unpaid
/// this cycle.
///
/// Salary detection logic mirrors `CategoryClassifier`: a `.credit`
/// transaction with `categorySlug == "salary"` OR (as a generous fallback)
/// any non-transfer credit ≥ ₹10,000 within the last 30 days. Either is
/// treated as "you have money — pay your bills".
///
/// Called from `AppContainer.init` (app launch), after `processPendingSMS`
/// finishes saving SMS-derived rows, and after the user manually adds /
/// updates / marks-paid a transaction. Cheap: a single read of the recent
/// transaction window + the recurring-bill list + one notification API call
/// per unpaid bill.
@MainActor
final class SalaryWatcher {

    private let transactionRepo: TransactionRepositoryImpl
    private let recurringBillRepo: RecurringBillRepositoryImpl

    /// Dedup key for "Salary detected — N bills due" — fires once per detected
    /// salary credit (keyed by the credit's transaction id) so the user isn't
    /// re-pinged on every state change.
    private static let salaryAnnouncementDedupKey = "salaryAnnouncementTxnIds"

    init(transactionRepo: TransactionRepositoryImpl,
         recurringBillRepo: RecurringBillRepositoryImpl) {
        self.transactionRepo = transactionRepo
        self.recurringBillRepo = recurringBillRepo
    }

    /// Re-evaluates salary + unpaid bills and (re)schedules reminders to match.
    /// Idempotent — `NotificationManager.scheduleBillReminders` cancels and
    /// re-adds per-bill so repeated calls don't pile up duplicate pending
    /// notifications.
    func handleStateChange() {
        let salary = recentSalary()
        let unpaid = recurringBillRepo.fetchDueThisCycle()

        if let salary, !unpaid.isEmpty {
            NotificationManager.shared.scheduleBillReminders(unpaid)
            announceSalaryIfNeeded(salary: salary, unpaidCount: unpaid.count)
        } else {
            // Either no recent salary, or nothing to pay. Tear down any stale
            // pending reminders so we don't ping for already-paid bills.
            NotificationManager.shared.cancelAllBillReminders(
                billIds: recurringBillRepo.fetchAll().map(\.id)
            )
        }
    }

    /// Most-recent salary credit within the last 30 days, or nil. Returns
    /// the underlying transaction so dedup can key the "salary detected"
    /// announcement off of it.
    func recentSalary() -> TransactionEntity? {
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let txns = transactionRepo.fetchAll(from: from)
        // Either classified as salary (categorySlug == "salary") OR a large
        // non-transfer credit that didn't get classified yet but plausibly is
        // a salary (mirrors classifyByAmount's ≥10k rule).
        return txns.first { txn in
            guard txn.isCredit else { return false }
            if txn.categorySlug == "salary" { return true }
            if txn.categorySlug == "transfer" || txn.categorySlug == "cc_payment" { return false }
            return txn.amount >= 10_000
        }
    }

    private func announceSalaryIfNeeded(salary: TransactionEntity, unpaidCount: Int) {
        var dedup = Set(UserDefaults.standard.stringArray(forKey: Self.salaryAnnouncementDedupKey) ?? [])
        let key = salary.id.uuidString
        guard !dedup.contains(key) else { return }
        dedup.insert(key)
        // Keep the dedup set bounded — last 20 salaries is plenty.
        if dedup.count > 20 {
            let kept = Array(dedup.suffix(20))
            UserDefaults.standard.set(kept, forKey: Self.salaryAnnouncementDedupKey)
        } else {
            UserDefaults.standard.set(Array(dedup), forKey: Self.salaryAnnouncementDedupKey)
        }
        NotificationManager.shared.fireSalaryDetectedAlert(unpaidBillCount: unpaidCount)
    }

    /// Wipe the dedup set — called from `AppContainer.clearAllData` so a
    /// fresh install doesn't see "Salary detected" suppressed by a key from
    /// a deleted transaction.
    static func resetSalaryAnnouncementDedup() {
        UserDefaults.standard.removeObject(forKey: salaryAnnouncementDedupKey)
    }
}
