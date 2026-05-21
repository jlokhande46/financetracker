import SwiftUI

struct CardDueCard: View {
    let statement: CardStatementEntity
    let onMarkPaid: () -> Void
    @AppStorage("hideAmounts") private var hideAmounts: Bool = false

    private var daysLabel: String {
        let d = statement.daysUntilDue
        if d < 0  { return "Overdue by \(-d)d" }
        if d == 0 { return "Due Today" }
        if d == 1 { return "Due Tomorrow" }
        return "Due in \(d) days"
    }

    private var accentColor: Color { Color(hex: statement.urgencyColor) }

    private var formattedTotal: String {
        if hideAmounts { return hiddenAmountPlaceholder }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₹"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: statement.totalDue as NSDecimalNumber) ?? "₹\(statement.totalDue)"
    }

    private var formattedDueDate: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: statement.dueDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {

            // Card header
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(Color(hex: statement.accountColorHex).opacity(0.25))
                        .frame(width: 32, height: 32)
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: statement.accountColorHex))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(statement.accountName)
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if let last4 = statement.accountLast4 {
                        Text("•••• \(last4)")
                            .font(.micro)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                Spacer()
            }

            // Amount
            Text(formattedTotal)
                .font(.amount(22, weight: .bold))
                .foregroundStyle(Color.textPrimary)

            // Due date badge
            HStack(spacing: 4) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)
                Text(daysLabel)
                    .font(.micro)
                    .foregroundStyle(accentColor)
                Text("· \(formattedDueDate)")
                    .font(.micro)
                    .foregroundStyle(Color.textTertiary)
            }

            if let min = statement.minimumDue, min < statement.totalDue {
                Text(hideAmounts
                     ? "Min \(hiddenAmountPlaceholder)"
                     : "Min ₹\(min.formatted(.number.precision(.fractionLength(0))))")
                    .font(.micro)
                    .foregroundStyle(Color.textSecondary)
            }

            // Mark paid button
            Button(action: onMarkPaid) {
                Text("Mark as Paid")
                    .font(.micro)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 6)
                    .background(accentColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.base)
        .frame(width: 160)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(accentColor.opacity(0.35), lineWidth: 1)
        )
    }
}
