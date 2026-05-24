import SwiftUI
import Charts

/// "What if you invested your wants spend in Nifty 50?" — a hypothetical
/// growth calculator that takes the user's actual monthly wants spend and
/// projects how much it would have grown at a configurable annual return.
struct WhatIfSimulatorCard: View {
    let monthlyWantsSpend: Decimal
    @State private var annualReturnPct: Double = 12
    @State private var years: Double = 5
    @AppStorage("hideAmounts") private var hideAmounts: Bool = false

    private var monthlyAmount: Double {
        Double(truncating: monthlyWantsSpend as NSDecimalNumber)
    }

    private var projectedValue: Double {
        sipFutureValue(monthly: monthlyAmount, annualRate: annualReturnPct / 100, years: years)
    }

    private var totalInvested: Double { monthlyAmount * years * 12 }
    private var totalReturns: Double { projectedValue - totalInvested }

    private var chartPoints: [(year: Int, value: Double)] {
        (0...Int(years)).map { y in
            (y, sipFutureValue(monthly: monthlyAmount, annualRate: annualReturnPct / 100, years: Double(y)))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            if monthlyAmount > 0 {
                projectionChart
                resultRow
                sliders
            } else {
                noDataState
            }
        }
        .cardStyle()
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "sparkle")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.brandAccent)
                Text("WHAT IF")
                    .font(.micro)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textSecondary)
                    .kerning(1.2)
            }
            Text("If you invested your monthly wants spend in Nifty 50...")
                .font(.bodyMedium)
                .foregroundStyle(Color.textPrimary)
        }
    }

    private var projectionChart: some View {
        Chart(chartPoints, id: \.year) { point in
            AreaMark(
                x: .value("Year", point.year),
                y: .value("Value", point.value)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [Color(hex: "#00D09C").opacity(0.3), Color(hex: "#00D09C").opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)
            LineMark(
                x: .value("Year", point.year),
                y: .value("Value", point.value)
            )
            .foregroundStyle(Color(hex: "#00D09C"))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel { Text("\(value.index)y") .font(.micro) }
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 100)
    }

    private var resultRow: some View {
        HStack(spacing: Spacing.md) {
            resultChip(label: "Invested", value: Decimal(totalInvested), color: .textSecondary)
            resultChip(label: "Returns", value: Decimal(totalReturns), color: .incomeGreen)
            resultChip(label: "Total", value: Decimal(projectedValue), color: Color(hex: "#00D09C"))
        }
    }

    private func resultChip(label: String, value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.micro)
                .foregroundStyle(Color.textTertiary)
            Text(value.compactString(hidden: hideAmounts))
                .font(.amount(14, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sliders: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Text("Return:")
                    .font(.micro)
                    .foregroundStyle(Color.textSecondary)
                Slider(value: $annualReturnPct, in: 6...18, step: 1)
                    .tint(Color.brandPrimary)
                Text("\(Int(annualReturnPct))%")
                    .font(.amount(13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 36)
            }
            HStack {
                Text("Years:")
                    .font(.micro)
                    .foregroundStyle(Color.textSecondary)
                Slider(value: $years, in: 1...20, step: 1)
                    .tint(Color.brandPrimary)
                Text("\(Int(years))")
                    .font(.amount(13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 36)
            }
        }
    }

    private var noDataState: some View {
        Text("No wants spend this month — nothing to simulate.")
            .font(.caption)
            .foregroundStyle(Color.textTertiary)
            .padding(.vertical, Spacing.md)
    }

    /// Standard SIP future value: FV = P × [(1+r)^n − 1] / r × (1+r)
    /// where P = monthly investment, r = monthly rate, n = total months.
    private func sipFutureValue(monthly: Double, annualRate: Double, years: Double) -> Double {
        let r = annualRate / 12
        let n = years * 12
        guard r > 0, n > 0 else { return monthly * n }
        let compound = pow(1 + r, n)
        return monthly * ((compound - 1) / r) * (1 + r)
    }
}
