import SwiftUI

/// Compact recurring-bill row used inside `RecurringBillsSection` and the
/// Dashboard "Bills Due" banner detail. Shows status, due day, expected
/// amount (when set), and a primary Mark-Paid action.
struct BillCard: View {
    let bill: RecurringBillEntity
    let salaryReceived: Bool
    var onMarkPaid: () -> Void = {}
    var onEdit: () -> Void = {}
    @AppStorage("hideAmounts") private var hideAmounts: Bool = false

    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()
    private static let paidDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    private var accent: Color { bill.type.color }
    private var statusColor: Color {
        if !bill.isDueThisCycle { return .incomeGreen }
        if bill.isOverdue { return .expenseRed }
        if bill.daysUntilDue <= 3 { return .warningAmber }
        return .textSecondary
    }

    private var statusText: String {
        if !bill.isDueThisCycle {
            if let paid = bill.lastPaidDate {
                return "Paid · \(Self.paidDateFormatter.string(from: paid))"
            }
            return "Paid"
        }
        if bill.isOverdue { return "Overdue \(-bill.daysUntilDue)d" }
        if bill.daysUntilDue == 0 { return "Due today" }
        if bill.daysUntilDue == 1 { return "Due tomorrow" }
        return "Due in \(bill.daysUntilDue)d"
    }

    private var ctaLabel: String {
        if !bill.isDueThisCycle { return "Paid" }
        if !salaryReceived { return "Mark paid" }
        return "Pay & link"
    }

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                header
                amountAndDue
                actionRow
            }
            .padding(Spacing.base)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(accent.opacity(bill.isDueThisCycle ? 0.30 : 0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(accent.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: bill.type.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.name)
                    .font(.titleMedium)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(bill.type.displayName)
                        .font(.micro)
                        .foregroundStyle(Color.textTertiary)
                    if bill.frequency != .monthly {
                        Text("·")
                            .font(.micro)
                            .foregroundStyle(Color.textTertiary)
                        Text(bill.frequency.displayName)
                            .font(.micro)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            statusBadge
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            if !bill.isDueThisCycle {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10))
            } else if bill.isOverdue {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
            }
            Text(statusText)
                .font(.micro)
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var amountAndDue: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AMOUNT")
                    .font(.micro)
                    .foregroundStyle(Color.textSecondary)
                if let amt = bill.amount {
                    Text(amt.currencyString(hidden: hideAmounts))
                        .font(.amount(18, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                } else {
                    Text("Varies")
                        .font(.amount(16, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("DUE")
                    .font(.micro)
                    .foregroundStyle(Color.textSecondary)
                Text(Self.dueDateFormatter.string(from: bill.nextDueDate))
                    .font(.amount(15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        if bill.isDueThisCycle {
            HStack {
                Spacer(minLength: 0)
                Button(action: onMarkPaid) {
                    Text(ctaLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 6)
                        .background(salaryReceived || !bill.isDueThisCycle ? Color.brandPrimary : statusColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
