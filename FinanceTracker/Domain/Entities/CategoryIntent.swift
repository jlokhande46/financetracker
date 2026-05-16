import SwiftUI

/// The 50/30/20 budgeting frame: Needs (essentials), Wants (lifestyle), Savings (future you).
enum CategoryIntent: String, CaseIterable, Identifiable {
    case need, want, saving
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .need:   return "Needs"
        case .want:   return "Wants"
        case .saving: return "Savings"
        }
    }

    var icon: String {
        switch self {
        case .need:   return "checkmark.shield.fill"
        case .want:   return "sparkles"
        case .saving: return "leaf.fill"
        }
    }

    var color: Color {
        switch self {
        case .need:   return Color(hex: "#3B82F6")
        case .want:   return Color(hex: "#F59E0B")
        case .saving: return Color(hex: "#10B981")
        }
    }

    /// Target percentage of total spend per the 50/30/20 rule.
    var targetPercent: Double {
        switch self {
        case .need:   return 50
        case .want:   return 30
        case .saving: return 20
        }
    }
}
