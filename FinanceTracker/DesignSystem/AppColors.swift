import SwiftUI

extension Color {
    // Backgrounds (adaptive — dark stays close to original, light is a clean grey/white)
    static let bgPrimary    = Color.adaptive(dark: "#0A0A0F", light: "#F5F5F7")
    static let bgSecondary  = Color.adaptive(dark: "#141418", light: "#FFFFFF")
    static let bgCard       = Color.adaptive(dark: "#1C1C24", light: "#FFFFFF")
    static let bgElevated   = Color.adaptive(dark: "#252530", light: "#E9E9EF")

    // Brand (same in both modes)
    static let brandPrimary = Color(hex: "#7B6EF6")
    static let brandAccent  = Color(hex: "#5E52E8")
    static let brandGlow    = Color(hex: "#7B6EF6").opacity(0.15)

    // Semantic
    static let incomeGreen  = Color(hex: "#00D09C")
    static let expenseRed   = Color(hex: "#FF6B6B")
    static let warningAmber = Color(hex: "#FFB545")
    static let neutralGray  = Color(hex: "#8E8E99")

    // Text (adaptive)
    static let textPrimary   = Color.adaptive(dark: "#FFFFFF", light: "#1C1C24")
    static let textSecondary = Color.adaptive(dark: "#8E8E99", light: "#6C6C72")
    static let textTertiary  = Color.adaptive(dark: "#48484E", light: "#B0B0B5")

    /// Build a Color that switches between two hex values based on UITraitCollection.
    static func adaptive(dark: String, light: String) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        })
    }

    // Category colors
    static let catFood          = Color(hex: "#FF8C42")
    static let catTravel        = Color(hex: "#4ECDC4")
    static let catShopping      = Color(hex: "#A855F7")
    static let catEntertainment = Color(hex: "#F59E0B")
    static let catBills         = Color(hex: "#3B82F6")
    static let catFuel          = Color(hex: "#EF4444")
    static let catHealth        = Color(hex: "#10B981")
    static let catInvestments   = Color(hex: "#00D09C")
    static let catSalary        = Color(hex: "#22C55E")
    static let catRent          = Color(hex: "#8B5CF6")
    static let catEMI           = Color(hex: "#F97316")
    static let catSubscriptions = Color(hex: "#EC4899")
    static let catTransfers     = Color(hex: "#64748B")
    static let catOthers        = Color(hex: "#94A3B8")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}
