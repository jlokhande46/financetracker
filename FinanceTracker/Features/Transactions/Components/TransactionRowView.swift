import SwiftUI

struct TransactionRowView: View {
    let transaction: TransactionEntity
    var accountChip: String? = nil
    var onTap: (() -> Void)? = nil

    private var category: CategoryEntity {
        CategoryEntity.find(slug: transaction.categorySlug)
    }

    private var amountColor: Color {
        transaction.isCredit ? .incomeGreen : .textPrimary
    }

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₹"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        let str = formatter.string(from: transaction.amount as NSDecimalNumber) ?? "₹\(transaction.amount)"
        return transaction.isCredit ? "+\(str)" : str
    }

    private var formattedTime: String? {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: transaction.date)
        // Hide midnight (PDF imports default to 00:00 — meaningless to display)
        if comps.hour == 0 && comps.minute == 0 { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: transaction.date)
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: Spacing.md) {

                // Pending review left accent
                if transaction.needsReview {
                    Rectangle()
                        .fill(Color.warningAmber)
                        .frame(width: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }

                // Category Icon
                CategoryIconView(slug: transaction.categorySlug, size: 44)

                // Center content
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Spacing.xs) {
                        Text(transaction.merchantName.isEmpty ? transaction.merchantRaw : transaction.merchantName)
                            .font(.titleMedium)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        if transaction.isRecurring {
                            Image(systemName: "repeat")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.brandPrimary)
                        }

                        if transaction.needsReview {
                            Text("Review")
                                .font(.micro)
                                .foregroundStyle(Color.warningAmber)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.warningAmber.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    Text(category.name)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)

                    HStack(spacing: Spacing.xs) {
                        SourceBadge(source: transaction.source)

                        if let time = formattedTime {
                            Text(time)
                                .font(.micro)
                                .foregroundStyle(Color.textTertiary)
                        }

                        if let chip = accountChip {
                            if formattedTime != nil {
                                Text("·")
                                    .font(.micro)
                                    .foregroundStyle(Color.textTertiary)
                            }
                            Image(systemName: "creditcard")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.textTertiary)
                            Text(chip)
                                .font(.micro)
                                .foregroundStyle(Color.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)

                // Right: Amount
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formattedAmount)
                        .font(.amount(15))
                        .foregroundStyle(amountColor)
                        .contentTransition(.numericText())
                }
            }
            .padding(.vertical, Spacing.md)
            .padding(.horizontal, transaction.needsReview ? 0 : Spacing.base)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section Header
struct TransactionSectionHeader: View {
    let title: String
    let total: Decimal
    let isExpense: Bool

    private var totalColor: Color {
        isExpense ? .expenseRed : .incomeGreen
    }

    private var formattedTotal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₹"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter.string(from: total as NSDecimalNumber) ?? "₹\(total)"
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .textCase(nil)

            Spacer()

            Text(formattedTotal)
                .font(.amount(13))
                .foregroundStyle(totalColor)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.xs)
        .background(Color.bgPrimary)
        .listRowInsets(EdgeInsets())
    }
}

#Preview {
    let txn = TransactionEntity(
        amount: 450,
        type: .debit,
        merchantRaw: "Swiggy",
        merchantName: "Swiggy",
        categorySlug: "food",
        source: .upi,
        confidence: 0.7,
        isConfirmed: false
    )
    List {
        TransactionRowView(transaction: txn)
            .listRowBackground(Color.bgCard)
            .listRowInsets(EdgeInsets())
    }
    .listStyle(.plain)
    .background(Color.bgPrimary)
}
