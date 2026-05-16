import SwiftUI

struct CategoryEntity: Identifiable, Equatable {
    let id: UUID
    var name: String
    var slug: String
    var icon: String
    var colorHex: String
    var isIncome: Bool
    var isTransfer: Bool
    var parentSlug: String?
    var isSystem: Bool
    var sortOrder: Int

    var color: Color { Color(hex: colorHex) }

    /// Maps every category to the 50/30/20 budgeting frame.
    /// Income categories return nil — they aren't part of the spend split.
    var intent: CategoryIntent? {
        if isIncome || isTransfer { return nil }
        switch slug {
        case "rent", "bills", "fuel", "health", "emi", "insurance", "education",
             "food", "groceries", "pets":
            return .need
        case "shopping", "entertainment", "travel", "subscriptions", "dining",
             "personal_care", "fitness", "gifts", "others":
            return .want
        case "investments", "donations":
            return .saving
        default:
            return .want
        }
    }

    static let system: [CategoryEntity] = [
        CategoryEntity(id: UUID(), name: "Food & Dining",    slug: "food",          icon: "fork.knife",                  colorHex: "#FF8C42", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 1),
        CategoryEntity(id: UUID(), name: "Groceries",        slug: "groceries",     icon: "cart.fill",                   colorHex: "#22C55E", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 2),
        CategoryEntity(id: UUID(), name: "Dining Out",       slug: "dining",        icon: "fork.knife.circle.fill",      colorHex: "#F97316", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 3),
        CategoryEntity(id: UUID(), name: "Travel",           slug: "travel",        icon: "airplane",                    colorHex: "#4ECDC4", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 4),
        CategoryEntity(id: UUID(), name: "Shopping",         slug: "shopping",      icon: "bag",                         colorHex: "#A855F7", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 5),
        CategoryEntity(id: UUID(), name: "Entertainment",    slug: "entertainment", icon: "popcorn",                     colorHex: "#F59E0B", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 6),
        CategoryEntity(id: UUID(), name: "Bills & Utilities",slug: "bills",         icon: "bolt",                        colorHex: "#3B82F6", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 7),
        CategoryEntity(id: UUID(), name: "Fuel",             slug: "fuel",          icon: "fuelpump",                    colorHex: "#EF4444", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 8),
        CategoryEntity(id: UUID(), name: "Health",           slug: "health",        icon: "heart.fill",                  colorHex: "#EF4444", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 9),
        CategoryEntity(id: UUID(), name: "Personal Care",    slug: "personal_care", icon: "scissors",                    colorHex: "#EC4899", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 10),
        CategoryEntity(id: UUID(), name: "Fitness",          slug: "fitness",       icon: "figure.run",                  colorHex: "#10B981", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 11),
        CategoryEntity(id: UUID(), name: "Pets",             slug: "pets",          icon: "pawprint.fill",               colorHex: "#8B5CF6", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 12),
        CategoryEntity(id: UUID(), name: "Gifts",            slug: "gifts",         icon: "gift.fill",                   colorHex: "#F472B6", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 13),
        CategoryEntity(id: UUID(), name: "Donations",        slug: "donations",     icon: "hand.raised.fill",            colorHex: "#06B6D4", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 14),
        CategoryEntity(id: UUID(), name: "Rent",             slug: "rent",          icon: "house",                       colorHex: "#8B5CF6", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 15),
        CategoryEntity(id: UUID(), name: "Subscriptions",    slug: "subscriptions", icon: "repeat",                      colorHex: "#EC4899", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 16),
        CategoryEntity(id: UUID(), name: "EMI",              slug: "emi",           icon: "calendar.badge.clock",        colorHex: "#F97316", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 17),
        CategoryEntity(id: UUID(), name: "Education",        slug: "education",     icon: "graduationcap",               colorHex: "#06B6D4", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 18),
        CategoryEntity(id: UUID(), name: "Insurance",        slug: "insurance",     icon: "shield",                      colorHex: "#84CC16", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 19),
        CategoryEntity(id: UUID(), name: "Investments",      slug: "investments",   icon: "chart.line.uptrend.xyaxis",   colorHex: "#00D09C", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 20),
        CategoryEntity(id: UUID(), name: "Others",           slug: "others",        icon: "ellipsis.circle",             colorHex: "#94A3B8", isIncome: false, isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 21),
        CategoryEntity(id: UUID(), name: "Salary",           slug: "salary",        icon: "banknote",                    colorHex: "#22C55E", isIncome: true,  isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 22),
        CategoryEntity(id: UUID(), name: "Freelance",        slug: "freelance",     icon: "laptopcomputer",              colorHex: "#4ADE80", isIncome: true,  isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 23),
        CategoryEntity(id: UUID(), name: "Refund",           slug: "refund",        icon: "arrow.uturn.left",            colorHex: "#34D399", isIncome: true,  isTransfer: false, parentSlug: nil, isSystem: true, sortOrder: 24),
        CategoryEntity(id: UUID(), name: "Transfer",         slug: "transfer",      icon: "arrow.left.arrow.right",      colorHex: "#64748B", isIncome: false, isTransfer: true,  parentSlug: nil, isSystem: true, sortOrder: 25),
        CategoryEntity(id: UUID(), name: "CC Payment",       slug: "cc_payment",    icon: "creditcard.and.123",          colorHex: "#A78BFA", isIncome: false, isTransfer: true,  parentSlug: nil, isSystem: true, sortOrder: 26),
    ]

    static func find(slug: String) -> CategoryEntity {
        system.first { $0.slug == slug } ?? system.last!
    }
}
