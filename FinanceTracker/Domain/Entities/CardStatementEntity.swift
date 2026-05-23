import Foundation

struct CardStatementEntity: Identifiable, Equatable {
    let id: UUID
    var accountId: UUID
    var accountName: String   // denormalised for display without a join
    var accountLast4: String?
    var accountColorHex: String
    var statementDate: Date?
    var dueDate: Date
    var totalDue: Decimal
    var minimumDue: Decimal?
    var isPaid: Bool
    var paidDate: Date?
    /// When the user marks the statement paid via the picker (or
    /// BillCycleManager auto-matches), this is the TransactionEntity.id
    /// of the cc_payment / transfer that settled it. Lets the user trace
    /// "ICICI Sapphiro paid via HDFC NEFT ₹35,000 on 28th".
    var paidTransactionId: UUID?
    let importedAt: Date

    // Helpers
    var daysUntilDue: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: dueDate)).day ?? 0
    }

    var isOverdue: Bool { daysUntilDue < 0 }

    var urgencyColor: String {
        if isOverdue { return "#EF4444" }
        if daysUntilDue <= 3 { return "#F59E0B" }
        return "#10B981"
    }

    init(
        id: UUID = UUID(),
        accountId: UUID,
        accountName: String,
        accountLast4: String? = nil,
        accountColorHex: String = "#7B6EF6",
        statementDate: Date? = nil,
        dueDate: Date,
        totalDue: Decimal,
        minimumDue: Decimal? = nil,
        isPaid: Bool = false,
        paidDate: Date? = nil,
        paidTransactionId: UUID? = nil,
        importedAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.accountName = accountName
        self.accountLast4 = accountLast4
        self.accountColorHex = accountColorHex
        self.statementDate = statementDate
        self.dueDate = dueDate
        self.totalDue = totalDue
        self.minimumDue = minimumDue
        self.isPaid = isPaid
        self.paidDate = paidDate
        self.paidTransactionId = paidTransactionId
        self.importedAt = importedAt
    }
}
