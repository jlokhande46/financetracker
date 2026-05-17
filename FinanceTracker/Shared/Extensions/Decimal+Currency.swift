import Foundation

extension Decimal {
    var currencyString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₹"
        formatter.currencyCode = "INR"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter.string(from: self as NSDecimalNumber) ?? "₹0"
    }

    var currencyStringWithDecimal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₹"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: self as NSDecimalNumber) ?? "₹0.00"
    }

    var compactString: String {
        let d = Double(truncating: self as NSDecimalNumber)
        switch abs(d) {
        case 1_00_00_000...: return String(format: "₹%.1fCr", d / 1_00_00_000)
        case 1_00_000...:    return String(format: "₹%.1fL", d / 1_00_000)
        case 1_000...:       return String(format: "₹%.1fK", d / 1_000)
        default:             return String(format: d.truncatingRemainder(dividingBy: 1) == 0 ? "₹%.0f" : "₹%.2f", d)
        }
    }
}

extension Double {
    var currencyString: String { Decimal(self).currencyString }
    var compactCurrency: String { Decimal(self).compactString }
}
