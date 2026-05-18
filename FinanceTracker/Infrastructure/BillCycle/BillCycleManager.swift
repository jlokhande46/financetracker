import Foundation

/// Owns the credit-card billing lifecycle:
///   1. For each CC account with statementDay/dueDay set, ensures a CardStatement
///      row exists for the current/last completed cycle (auto-generated on the
///      statement day from the sum of debits on that card).
///   2. On every transaction save, checks whether an unpaid statement should be
///      marked paid by a matching CC-payment transaction (amount within ±1%).
///   3. Schedules daily reminders from statement date through due date for any
///      unpaid statement.
@MainActor
final class BillCycleManager {

    private let accountRepo: AccountRepositoryImpl
    private let statementRepo: CardStatementRepositoryImpl
    private let transactionRepo: TransactionRepositoryImpl

    init(accountRepo: AccountRepositoryImpl,
         statementRepo: CardStatementRepositoryImpl,
         transactionRepo: TransactionRepositoryImpl) {
        self.accountRepo = accountRepo
        self.statementRepo = statementRepo
        self.transactionRepo = transactionRepo
    }

    // MARK: - Public API

    /// Run a full sweep — call on app launch and when accounts change.
    func runDailySweep(now: Date = Date()) {
        let accounts = accountRepo.fetchAll().filter { $0.type == .credit && $0.statementDay != nil && $0.dueDay != nil }
        for account in accounts {
            ensureStatement(for: account, now: now)
        }
        rescheduleAllNotifications()
        autoMarkPaidStatements()
    }

    /// Called whenever a transaction is added/updated — looks for a CC payment
    /// that closes out an unpaid statement.
    func handleTransactionChange() {
        autoMarkPaidStatements()
    }

    // MARK: - Statement generation

    /// For an account whose cycle days are set, decide what the "current" cycle
    /// statement date is. If statementDay has already passed this month, the
    /// cycle just closed; otherwise it closed last month. Either way: ensure a
    /// CardStatement record exists for that cycle.
    private func ensureStatement(for account: AccountEntity, now: Date) {
        guard let statementDay = account.statementDay,
              let dueDay = account.dueDay else { return }
        let cal = Calendar.current

        let cycleEnd = mostRecentDay(statementDay, before: now, calendar: cal)
        let cycleStart = mostRecentDay(statementDay, before: cycleEnd.addingTimeInterval(-1), calendar: cal)
        let dueDate = nextDay(dueDay, after: cycleEnd, calendar: cal)

        // If we already have a statement for this cycle, skip
        let existing = statementRepo.fetchAll().first { stmt in
            stmt.accountId == account.id && cal.isDate(stmt.dueDate, inSameDayAs: dueDate)
        }
        if existing != nil { return }

        // Sum debits charged to this card between cycleStart..cycleEnd
        let txnsOnCard = transactionRepo.fetchAll().filter {
            $0.accountId == account.id && $0.isDebit && $0.date >= cycleStart && $0.date <= cycleEnd
        }
        let total = txnsOnCard.reduce(Decimal(0)) { $0 + $1.amount }
        guard total > 0 else { return }  // nothing to bill

        let statement = CardStatementEntity(
            accountId: account.id,
            accountName: account.name,
            accountLast4: account.last4,
            accountColorHex: account.colorHex,
            statementDate: cycleEnd,
            dueDate: dueDate,
            totalDue: total,
            minimumDue: nil,
            isPaid: false
        )
        statementRepo.save(statement)
        NotificationManager.shared.scheduleReminders(for: statement)
    }

    // MARK: - Auto mark-paid

    /// For every unpaid statement, look for a CC-payment transaction posted
    /// after the statement date with an amount within 1% of the total due.
    /// If found, mark the statement paid and cancel notifications.
    private func autoMarkPaidStatements() {
        let unpaid = statementRepo.fetchUnpaid()
        let allTxns = transactionRepo.fetchAll()

        for stmt in unpaid {
            let candidates = allTxns.filter { txn in
                txn.categorySlug == "cc_payment" &&
                (txn.accountId == stmt.accountId || txn.accountId == nil) &&
                txn.date >= (stmt.statementDate ?? stmt.dueDate.addingTimeInterval(-30 * 86400))
            }
            let match = candidates.first { txn in
                // Within ±1% of the total due — handles small rounding diffs.
                let diff = abs(txn.amount - stmt.totalDue)
                return diff <= max(Decimal(1), stmt.totalDue * Decimal(0.01))
            }
            if match != nil {
                statementRepo.markPaid(stmt.id)
                NotificationManager.shared.cancelReminders(for: stmt.id)
            }
        }
    }

    // MARK: - Notification refresh

    private func rescheduleAllNotifications() {
        for stmt in statementRepo.fetchUnpaid() {
            NotificationManager.shared.scheduleReminders(for: stmt)
        }
    }

    // MARK: - Calendar helpers

    /// The most recent occurrence of `day` strictly before (or equal to) `reference`.
    private func mostRecentDay(_ day: Int, before reference: Date, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month], from: reference)
        comps.day = day
        let thisMonth = calendar.date(from: comps) ?? reference
        if thisMonth <= reference { return thisMonth }
        // Step back one month using Calendar arithmetic to handle Jan → Dec wraparound
        return calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? reference
    }

    /// The next occurrence of `day` strictly after `reference`.
    private func nextDay(_ day: Int, after reference: Date, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month], from: reference)
        comps.day = day
        let thisMonth = calendar.date(from: comps) ?? reference
        if thisMonth > reference { return thisMonth }
        // Step forward one month using Calendar arithmetic to handle Dec → Jan wraparound
        return calendar.date(byAdding: .month, value: 1, to: thisMonth) ?? reference
    }
}
