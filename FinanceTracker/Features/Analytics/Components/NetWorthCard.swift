import SwiftUI
import Charts

/// Shows the user's current net worth (assets − liabilities) with a
/// breakdown pie and a trailing-12-month trend line. Tapping "Manage"
/// opens the investment holdings sheet.
struct NetWorthCard: View {
    let snapshot: NetWorthTracker.Snapshot
    let history: [NetWorthTracker.MonthPoint]
    var onManageInvestments: () -> Void = {}
    @AppStorage("hideAmounts") private var hideAmounts: Bool = false

    private var netWorthColor: Color {
        snapshot.netWorth >= 0 ? .incomeGreen : .expenseRed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            breakdownRow
            if history.count >= 2 { trendChart }
        }
        .cardStyle()
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NET WORTH")
                    .font(.micro)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textSecondary)
                    .kerning(1.2)
                Text(snapshot.netWorth.currencyString(hidden: hideAmounts))
                    .font(.amount(32, weight: .bold))
                    .foregroundStyle(netWorthColor)
                    .contentTransition(.numericText())
                if snapshot.investmentReturns != 0 && !hideAmounts {
                    let sign = snapshot.investmentReturns >= 0 ? "+" : ""
                    Text("\(sign)\(snapshot.investmentReturns.compactString) returns")
                        .font(.caption)
                        .foregroundStyle(snapshot.investmentReturns >= 0 ? Color.incomeGreen : Color.expenseRed)
                }
            }
            Spacer()
            Button(action: onManageInvestments) {
                HStack(spacing: 4) {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Manage")
                        .font(.caption)
                }
                .foregroundStyle(Color.brandPrimary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.brandPrimary.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var breakdownRow: some View {
        HStack(spacing: Spacing.md) {
            breakdownChip(label: "Savings", value: snapshot.savings, color: .incomeGreen, icon: "building.columns.fill")
            breakdownChip(label: "Investments", value: snapshot.investments, color: Color(hex: "#00D09C"), icon: "chart.line.uptrend.xyaxis")
            breakdownChip(label: "CC Dues", value: snapshot.liabilities, color: .expenseRed, icon: "creditcard.fill")
        }
    }

    private func breakdownChip(label: String, value: Decimal, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                Text(label)
                    .font(.micro)
                    .foregroundStyle(Color.textSecondary)
            }
            Text(value.compactString(hidden: hideAmounts))
                .font(.amount(14, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(Color.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("12-MONTH TREND")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
            Chart(history) { point in
                LineMark(
                    x: .value("Month", point.month),
                    y: .value("Net Worth", point.value)
                )
                .foregroundStyle(netWorthColor)
                .interpolationMethod(.catmullRom)
                AreaMark(
                    x: .value("Month", point.month),
                    y: .value("Net Worth", point.value)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [netWorthColor.opacity(0.2), netWorthColor.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 80)
        }
    }
}
