import Foundation
import SwiftData

@Model
final class CardStatementModel {
    @Attribute(.unique) var id: UUID = UUID()
    var accountId: UUID = UUID()
    var accountName: String = ""
    var accountLast4: String?
    var accountColorHex: String = "#7B6EF6"
    var statementDate: Date?
    var dueDate: Date = Date()
    var totalDueDouble: Double = 0
    var minimumDueDouble: Double?
    var isPaid: Bool = false
    var paidDate: Date?
    /// Optional link to the cc_payment / transfer transaction that settled
    /// this statement. SwiftData auto-migrates existing rows to nil.
    var paidTransactionId: UUID?
    var importedAt: Date = Date()

    init(
        id: UUID = UUID(),
        accountId: UUID,
        accountName: String,
        accountLast4: String? = nil,
        accountColorHex: String = "#7B6EF6",
        statementDate: Date? = nil,
        dueDate: Date,
        totalDueDouble: Double,
        minimumDueDouble: Double? = nil,
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
        self.totalDueDouble = totalDueDouble
        self.minimumDueDouble = minimumDueDouble
        self.isPaid = isPaid
        self.paidDate = paidDate
        self.paidTransactionId = paidTransactionId
        self.importedAt = importedAt
    }

    func toEntity() -> CardStatementEntity {
        CardStatementEntity(
            id: id,
            accountId: accountId,
            accountName: accountName,
            accountLast4: accountLast4,
            accountColorHex: accountColorHex,
            statementDate: statementDate,
            dueDate: dueDate,
            totalDue: Decimal(totalDueDouble),
            minimumDue: minimumDueDouble.map { Decimal($0) },
            isPaid: isPaid,
            paidDate: paidDate,
            paidTransactionId: paidTransactionId,
            importedAt: importedAt
        )
    }
}
