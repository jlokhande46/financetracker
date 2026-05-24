import SwiftUI

/// A manually-tracked investment holding — mutual funds, stocks, FDs, gold,
/// PPF/NPS, etc. The user updates `currentValue` periodically (monthly or
/// whenever they check their portfolio). No live NAV fetch — the app stays
/// offline-first and API-key-free.
struct InvestmentHoldingEntity: Identifiable, Equatable {
    let id: UUID
    var name: String
    var type: InvestmentType
    var currentValue: Decimal
    var investedAmount: Decimal
    var lastUpdated: Date
    var notes: String?
    var createdAt: Date

    var returns: Decimal { currentValue - investedAmount }
    var returnsPct: Double {
        guard investedAmount > 0 else { return 0 }
        return Double(truncating: (returns / investedAmount * 100) as NSDecimalNumber)
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: InvestmentType = .mutualFund,
        currentValue: Decimal,
        investedAmount: Decimal = 0,
        lastUpdated: Date = Date(),
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.currentValue = currentValue
        self.investedAmount = investedAmount
        self.lastUpdated = lastUpdated
        self.notes = notes
        self.createdAt = createdAt
    }
}

enum InvestmentType: String, Codable, CaseIterable, Identifiable {
    case mutualFund = "mf"
    case stock
    case fd
    case gold
    case ppfNps = "ppf_nps"
    case crypto
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mutualFund: return "Mutual Fund"
        case .stock:      return "Stocks"
        case .fd:         return "Fixed Deposit"
        case .gold:       return "Gold"
        case .ppfNps:     return "PPF / NPS"
        case .crypto:     return "Crypto"
        case .other:      return "Other"
        }
    }

    var icon: String {
        switch self {
        case .mutualFund: return "chart.line.uptrend.xyaxis"
        case .stock:      return "chart.bar.fill"
        case .fd:         return "building.columns.fill"
        case .gold:       return "bitcoinsign.circle.fill"
        case .ppfNps:     return "lock.shield.fill"
        case .crypto:     return "c.circle.fill"
        case .other:      return "banknote.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .mutualFund: return "#00D09C"
        case .stock:      return "#3B82F6"
        case .fd:         return "#F59E0B"
        case .gold:       return "#EAB308"
        case .ppfNps:     return "#8B5CF6"
        case .crypto:     return "#F97316"
        case .other:      return "#94A3B8"
        }
    }

    var color: Color { Color(hex: colorHex) }
}
