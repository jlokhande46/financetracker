import Foundation
import SwiftData

@Model
final class AccountModel {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var bankName: String = ""
    var typeRaw: String = "savings"
    var last4: String?
    var balance: Double = 0
    var creditLimit: Double?
    var colorHex: String = "#7B6EF6"
    var isActive: Bool = true
    /// Day of month the credit-card statement is generated (auto-migrated to nil).
    var statementDay: Int?
    /// Day of month the bill is due (auto-migrated to nil).
    var dueDay: Int?
    var createdAt: Date = Date()

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .savings }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        bankName: String = "",
        typeRaw: String = "savings",
        last4: String? = nil,
        balance: Double = 0,
        creditLimit: Double? = nil,
        colorHex: String = "#7B6EF6",
        isActive: Bool = true,
        statementDay: Int? = nil,
        dueDay: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.bankName = bankName
        self.typeRaw = typeRaw
        self.last4 = last4
        self.balance = balance
        self.creditLimit = creditLimit
        self.colorHex = colorHex
        self.isActive = isActive
        self.statementDay = statementDay
        self.dueDay = dueDay
        self.createdAt = createdAt
    }

    func toEntity() -> AccountEntity {
        AccountEntity(
            id: id,
            name: name,
            bankName: bankName,
            type: type,
            last4: last4,
            balance: Decimal(balance),
            creditLimit: creditLimit.map { Decimal($0) },
            colorHex: colorHex,
            isActive: isActive,
            statementDay: statementDay,
            dueDay: dueDay,
            createdAt: createdAt
        )
    }
}
