import SwiftUI

struct GoalEntity: Identifiable, Equatable {
    let id: UUID
    var name: String
    var type: GoalType
    var targetAmount: Decimal
    var currentAmount: Decimal
    var targetDate: Date?
    var notes: String?
    var isCompleted: Bool
    var createdAt: Date

    var progressFraction: Double {
        guard targetAmount > 0 else { return 0 }
        let pct = (currentAmount / targetAmount) as NSDecimalNumber
        return min(1.0, max(0.0, Double(truncating: pct)))
    }

    var remaining: Decimal {
        max(0, targetAmount - currentAmount)
    }

    var daysRemaining: Int? {
        guard let target = targetDate else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end   = calendar.startOfDay(for: target)
        return calendar.dateComponents([.day], from: start, to: end).day
    }

    var monthlyRequired: Decimal? {
        guard let days = daysRemaining, days > 0 else { return nil }
        let months = max(1.0, Double(days) / 30.0)
        let monthly = Double(truncating: remaining as NSDecimalNumber) / months
        return Decimal(monthly)
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: GoalType = .other,
        targetAmount: Decimal,
        currentAmount: Decimal = 0,
        targetDate: Date? = nil,
        notes: String? = nil,
        isCompleted: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.targetDate = targetDate
        self.notes = notes
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}

enum GoalType: String, CaseIterable, Codable {
    case travel, home, vehicle, education, emergency, retirement, gadget, wedding, other

    var displayName: String {
        switch self {
        case .travel:     return "Travel"
        case .home:       return "Home"
        case .vehicle:    return "Vehicle"
        case .education:  return "Education"
        case .emergency:  return "Emergency Fund"
        case .retirement: return "Retirement"
        case .gadget:     return "Gadget"
        case .wedding:    return "Wedding"
        case .other:      return "Other"
        }
    }

    var icon: String {
        switch self {
        case .travel:     return "airplane"
        case .home:       return "house.fill"
        case .vehicle:    return "car.fill"
        case .education:  return "graduationcap.fill"
        case .emergency:  return "shield.lefthalf.filled"
        case .retirement: return "leaf.fill"
        case .gadget:     return "iphone"
        case .wedding:    return "heart.fill"
        case .other:      return "target"
        }
    }

    var colorHex: String {
        switch self {
        case .travel:     return "#4ECDC4"
        case .home:       return "#8B5CF6"
        case .vehicle:    return "#EF4444"
        case .education:  return "#06B6D4"
        case .emergency:  return "#F59E0B"
        case .retirement: return "#10B981"
        case .gadget:     return "#3B82F6"
        case .wedding:    return "#EC4899"
        case .other:      return "#7B6EF6"
        }
    }

    var color: Color { Color(hex: colorHex) }
}
