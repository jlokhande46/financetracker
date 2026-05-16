import SwiftUI
import Charts

struct CashFlowChart: View {

    let dayWiseSpend: [DaySpend]
    @State private var animateChart = false
    @State private var selectedDay: DaySpend?

    private var averageSpend: Double {
        guard !dayWiseSpend.isEmpty else { return 0 }
        let nonZero = dayWiseSpend.filter { $0.amount > 0 }
        guard !nonZero.isEmpty else { return 0 }
        let total = nonZero.reduce(Decimal(0)) { $0 + $1.amount }
        return Double(truncating: (total / Decimal(nonZero.count)) as NSDecimalNumber)
    }

    private var maxSpend: Double {
        dayWiseSpend.map { Double(truncating: $0.amount as NSDecimalNumber) }.max() ?? 1
    }

    private var xAxisValues: [Date] {
        let cal = Calendar.current
        return [1, 5, 10, 15, 20, 25].compactMap { day -> Date? in
            guard day <= dayWiseSpend.count else { return nil }
            return dayWiseSpend.first(where: { cal.component(.day, from: $0.date) == day })?.date
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CASH FLOW")
                        .font(.micro)
                        .fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                        .kerning(1.2)
                    Text("Daily Spending")
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)
                }
                Spacer()

                // Selected day tooltip
                if let selected = selectedDay, selected.amount > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(selected.date.dayMonthYear)
                            .font(.micro)
                            .foregroundColor(.textSecondary)
                        Text(selected.amount.currencyString)
                            .font(Font.amount(14))
                            .fontWeight(.semibold)
                            .foregroundColor(.textPrimary)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Daily avg")
                            .font(.micro)
                            .foregroundColor(.textSecondary)
                        Text(Decimal(averageSpend).compactString)
                            .font(Font.amount(14))
                            .fontWeight(.semibold)
                            .foregroundColor(.warningAmber)
                    }
                }
            }
            .animation(.springy, value: selectedDay?.id)

            // Chart
            Chart {
                ForEach(dayWiseSpend) { day in
                    let value = animateChart ? Double(truncating: day.amount as NSDecimalNumber) : 0
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Amount", value)
                    )
                    .foregroundStyle(
                        selectedDay?.id == day.id
                            ? Color.brandPrimary
                            : Color.brandPrimary.opacity(day.amount > 0 ? 0.75 : 0.15)
                    )
                    .cornerRadius(3)

                    if let sel = selectedDay, sel.id == day.id {
                        RuleMark(x: .value("Selected", day.date, unit: .day))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(Color.brandPrimary.opacity(0.5))
                    }
                }

                // Average line
                if averageSpend > 0 {
                    RuleMark(y: .value("Average", averageSpend))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundStyle(Color.warningAmber.opacity(0.8))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("avg")
                                .font(.micro)
                                .foregroundColor(.warningAmber.opacity(0.8))
                                .padding(.horizontal, 4)
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisValues) { value in
                    AxisValueLabel(format: .dateTime.day())
                        .foregroundStyle(Color.textSecondary)
                        .font(.micro)
                    AxisGridLine()
                        .foregroundStyle(Color.chartGrid)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    if let amount = value.as(Double.self) {
                        AxisValueLabel {
                            Text(formatYLabel(amount))
                                .font(.micro)
                                .foregroundColor(.textSecondary)
                        }
                        AxisGridLine()
                            .foregroundStyle(Color.chartGrid)
                    }
                }
            }
            // chartXSelection drives selection internally without per-pixel re-renders.
            // Wrapped in a non-animating transaction so the parent's .animation(value:)
            // doesn't fire on every move and cause the chart to flicker.
            .chartXSelection(value: Binding(
                get: { selectedDay?.date },
                set: { newDate in
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        if let d = newDate {
                            let cal = Calendar.current
                            selectedDay = dayWiseSpend.min(by: {
                                abs(cal.startOfDay(for: $0.date).timeIntervalSince(cal.startOfDay(for: d))) <
                                abs(cal.startOfDay(for: $1.date).timeIntervalSince(cal.startOfDay(for: d)))
                            })
                        } else {
                            selectedDay = nil
                        }
                    }
                }
            ))
            .frame(height: 160)
            .animation(.easeOut(duration: 0.7), value: animateChart)
        }
        .cardStyle()
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) {
                animateChart = true
            }
        }
    }

    private func formatYLabel(_ amount: Double) -> String {
        if amount >= 100_000 { return "₹\(Int(amount / 100_000))L" }
        if amount >= 1_000 { return "₹\(Int(amount / 1_000))K" }
        return "₹\(Int(amount))"
    }
}

// warningAmber color extension reference - defined in DashboardView.swift
