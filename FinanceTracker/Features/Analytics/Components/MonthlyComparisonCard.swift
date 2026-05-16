import SwiftUI

struct MonthlyComparisonCard: View {

    let current: MonthlyAnalysis
    let previous: MonthlyAnalysis?

    private struct ComparisonRow: Identifiable {
        let id: String
        let categorySlug: String
        let currentAmount: Decimal
        let previousAmount: Decimal
        var changePercent: Double {
            guard previousAmount > 0 else { return currentAmount > 0 ? 100 : 0 }
            return Double(truncating: ((currentAmount - previousAmount) / previousAmount * 100) as NSDecimalNumber)
        }
        var absoluteChange: Decimal { currentAmount - previousAmount }
    }

    private var rows: [ComparisonRow] {
        var result: [ComparisonRow] = []

        for catSpend in current.categoryBreakdown {
            let prevAmount = previous?.categoryBreakdown
                .first(where: { $0.categorySlug == catSpend.categorySlug })?.amount ?? 0
            result.append(ComparisonRow(
                id: catSpend.categorySlug,
                categorySlug: catSpend.categorySlug,
                currentAmount: catSpend.amount,
                previousAmount: prevAmount
            ))
        }

        // Add categories that appear in previous but not current
        if let prev = previous {
            for catSpend in prev.categoryBreakdown where !result.contains(where: { $0.categorySlug == catSpend.categorySlug }) {
                result.append(ComparisonRow(
                    id: catSpend.categorySlug,
                    categorySlug: catSpend.categorySlug,
                    currentAmount: 0,
                    previousAmount: catSpend.amount
                ))
            }
        }

        return result.sorted { abs($0.absoluteChange) > abs($1.absoluteChange) }
    }

    private var currentMonthLabel: String {
        current.month.shortMonthYear
    }

    private var previousMonthLabel: String {
        guard let prev = previous else { return "Prev" }
        return prev.month.shortMonthYear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MONTHLY COMPARISON")
                        .font(.micro)
                        .fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                        .kerning(1.2)
                    Text("vs Last Month")
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)
                }
                Spacer()
            }

            // Column headers
            HStack {
                Text("Category")
                    .font(.micro)
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(previousMonthLabel)
                    .font(.micro)
                    .foregroundColor(.textSecondary)
                    .frame(width: 70, alignment: .trailing)

                Text(currentMonthLabel)
                    .font(.micro)
                    .foregroundColor(.textSecondary)
                    .frame(width: 70, alignment: .trailing)

                Text("Change")
                    .font(.micro)
                    .foregroundColor(.textSecondary)
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.bottom, 2)

            Divider()
                .background(Color.white.opacity(0.08))

            // Rows
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    comparisonRow(row)

                    Divider()
                        .background(Color.white.opacity(0.05))
                }
            }

            // Total row
            Divider()
                .background(Color.white.opacity(0.15))
                .padding(.top, 4)

            totalRow
        }
        .cardStyle()
    }

    private func comparisonRow(_ row: ComparisonRow) -> some View {
        let cat = CategoryEntity.find(slug: row.categorySlug)
        let change = row.changePercent
        let isIncrease = change > 0

        return HStack {
            // Category
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(cat.color.opacity(0.2))
                        .frame(width: 24, height: 24)
                    Image(systemName: cat.icon)
                        .font(.system(size: 12))
                }
                Text(cat.name)
                    .font(.caption)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Previous
            Text(row.previousAmount > 0 ? row.previousAmount.compactString : "—")
                .font(Font.amount(12))
                .foregroundColor(.textSecondary)
                .frame(width: 70, alignment: .trailing)

            // Current
            Text(row.currentAmount > 0 ? row.currentAmount.compactString : "—")
                .font(Font.amount(12))
                .foregroundColor(.textPrimary)
                .frame(width: 70, alignment: .trailing)

            // Change
            HStack(spacing: 2) {
                Image(systemName: isIncrease ? "arrow.up" : "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                Text(String(format: "%.0f%%", abs(change)))
                    .font(.micro)
                    .fontWeight(.semibold)
            }
            .foregroundColor(row.previousAmount == 0 ? .textSecondary : (isIncrease ? .expenseRed : .incomeGreen))
            .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, Spacing.sm)
    }

    private var totalRow: some View {
        let prevTotal = previous?.totalExpenses ?? 0
        let currTotal = current.totalExpenses
        let change = prevTotal > 0
            ? Double(truncating: ((currTotal - prevTotal) / prevTotal * 100) as NSDecimalNumber)
            : 0
        let isIncrease = change > 0

        return HStack {
            Text("Total Expenses")
                .font(.bodyMedium)
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(prevTotal > 0 ? prevTotal.compactString : "—")
                .font(Font.amount(13))
                .fontWeight(.semibold)
                .foregroundColor(.textSecondary)
                .frame(width: 70, alignment: .trailing)

            Text(currTotal.compactString)
                .font(Font.amount(13))
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)
                .frame(width: 70, alignment: .trailing)

            HStack(spacing: 2) {
                if prevTotal > 0 {
                    Image(systemName: isIncrease ? "arrow.up" : "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                    Text(String(format: "%.0f%%", abs(change)))
                        .font(.micro)
                        .fontWeight(.bold)
                }
            }
            .foregroundColor(isIncrease ? .expenseRed : .incomeGreen)
            .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, Spacing.sm)
        .padding(Spacing.sm)
        .background(Color.white.opacity(0.04))
        .cornerRadius(Radius.sm)
    }
}
