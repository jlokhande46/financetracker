import Foundation

struct AccountEntity: Identifiable, Equatable {
    let id: UUID
    var name: String
    var bankName: String
    var type: AccountType
    var last4: String?
    var balance: Decimal
    var creditLimit: Decimal?
    var colorHex: String
    var isActive: Bool
    /// Day of month the credit card statement is generated (1-31). Only meaningful
    /// for credit-type accounts. Used by BillCycleManager to auto-create statements.
    var statementDay: Int?
    /// Day of month the bill is due. Cycle: statement → due (next occurrence of dueDay).
    var dueDay: Int?
    var createdAt: Date

    var availableCredit: Decimal? {
        guard type == .credit, let limit = creditLimit else { return nil }
        return limit - balance
    }

    var utilizationPercent: Double? {
        guard type == .credit, let limit = creditLimit, limit > 0 else { return nil }
        return Double(truncating: (balance / limit * 100) as NSDecimalNumber)
    }

    init(
        id: UUID = UUID(),
        name: String,
        bankName: String = "",
        type: AccountType,
        last4: String? = nil,
        balance: Decimal = 0,
        creditLimit: Decimal? = nil,
        colorHex: String = "#7B6EF6",
        isActive: Bool = true,
        statementDay: Int? = nil,
        dueDay: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.bankName = bankName
        self.type = type
        self.last4 = last4
        self.balance = balance
        self.creditLimit = creditLimit
        self.colorHex = colorHex
        self.isActive = isActive
        self.statementDay = statementDay
        self.dueDay = dueDay
        self.createdAt = createdAt
    }
}

enum AccountType: String, Codable, CaseIterable {
    case savings    = "savings"
    case current    = "current"
    case credit     = "credit"
    case wallet     = "wallet"
    case investment = "investment"

    var displayName: String {
        switch self {
        case .savings:    return "Savings Account"
        case .current:    return "Current Account"
        case .credit:     return "Credit Card"
        case .wallet:     return "Wallet"
        case .investment: return "Investment"
        }
    }

    var icon: String {
        switch self {
        case .savings:    return "building.columns"
        case .current:    return "building.columns.fill"
        case .credit:     return "creditcard"
        case .wallet:     return "wallet.pass"
        case .investment: return "chart.line.uptrend.xyaxis"
        }
    }
}
