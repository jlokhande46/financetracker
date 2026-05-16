import SwiftUI

struct AmountLabel: View {
    let amount: Decimal
    let type: TransactionType
    var size: CGFloat = 17
    var showSign: Bool = true
    var colorOverride: Color? = nil

    private var displayColor: Color {
        if let override = colorOverride { return override }
        return type == .credit ? .incomeGreen : .textPrimary
    }

    private var prefix: String {
        guard showSign else { return "" }
        return type == .credit ? "+" : "-"
    }

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₹"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter.string(from: amount as NSDecimalNumber) ?? "₹\(amount)"
    }

    var body: some View {
        Text("\(prefix)\(formattedAmount)")
            .font(.amount(size))
            .foregroundStyle(displayColor)
            .contentTransition(.numericText())
    }
}

#Preview {
    VStack(spacing: 16) {
        AmountLabel(amount: 1250.50, type: .debit)
        AmountLabel(amount: 45000, type: .credit)
        AmountLabel(amount: 8999, type: .debit, size: 34)
    }
    .padding()
    .background(Color.bgPrimary)
}
