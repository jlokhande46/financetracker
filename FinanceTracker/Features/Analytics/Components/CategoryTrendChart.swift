import SwiftUI
import Charts

struct CategoryTrendChart: View {

    let last6Months: [MonthlyAnalysis]
    let selectedCategory: String?

    @State private var animateChart = false
    @State private var highlightedMonth: Date?

    private var topCategories: [String] {
        var catTotals: [String: Decimal] = [:]
        for analysis in last6Months {
            for cat in analysis.categoryBreakdown {
                catTotals[cat.categorySlug] = (catTotals[cat.categorySlug] ?? 0) + cat.amount
            }
        }
        if let sel = selectedCategory {
            return [sel]
        }
        return Array(catTotals.sorted { $0.value > $1.value }.prefix(4).map(\.key))
    }

    private var chartData: [(month: Date, categorySlug: String, amount: Double)] {
        var result: [(month: Date, categorySlug: String, amount: Double)] = []
        let cats = topCategories
        for analysis in last6Months {
            for cat in cats {
                let spend = analysis.categoryBreakdown.first(where: { $0.categorySlug == cat })
                let amount = spend.map { Double(truncating: $0.amount as NSDecimalNumber) } ?? 0
                result.append((month: analysis.month, categorySlug: cat, amount: amount))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SPENDING TRENDS")
                        .font(.micro)
                        .fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                        .kerning(1.2)
                    Text(selectedCategory != nil
                         ? CategoryEntity.find(slug: selectedCategory!).name
                         : "Last 6 Months")
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)
                        .animation(.springy, value: selectedCategory)
                }
                Spacer()

                if let sel = selectedCategory {
                    let cat = CategoryEntity.find(slug: sel)
                    HStack(spacing: 4) {
                        Image(systemName: cat.icon)
                            .font(.system(size: 14))
                        Text(cat.name)
                            .font(.caption)
                            .foregroundColor(cat.color)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    .background(cat.color.opacity(0.15))
                    .cornerRadius(Radius.sm)
                }
            }

            // Chart
            if chartData.isEmpty {
                emptyState
            } else {
                Chart(chartData, id: \.month) { item in
                    let cat = CategoryEntity.find(slug: item.categorySlug)
                    BarMark(
                        x: .value("Month", item.month, unit: .month),
                        y: .value("Amount", animateChart ? item.amount : 0),
                        width: .ratio(topCategories.count == 1 ? 0.5 : 0.85)
                    )
                    .foregroundStyle(
                        highlightedMonth == nil || highlightedMonth == item.month
                            ? cat.color.opacity(0.85)
                            : cat.color.opacity(0.2)
                    )
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: last6Months.map(\.month)) { value in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                            .foregroundStyle(Color.textSecondary)
                            .font(.micro)
                        AxisGridLine()
                            .foregroundStyle(Color.white.opacity(0.05))
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
                                .foregroundStyle(Color.white.opacity(0.05))
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let x = value.location.x - geo.frame(in: .local).minX
                                        if let date: Date = proxy.value(atX: x, as: Date.self) {
                                            highlightedMonth = last6Months.min(by: {
                                                abs($0.month.timeIntervalSince(date)) <
                                                abs($1.month.timeIntervalSince(date))
                                            })?.month
                                        }
                                    }
                                    .onEnded { _ in
                                        withAnimation(.easeOut(duration: 0.25)) {
                                            highlightedMonth = nil
                                        }
                                    }
                            )
                    }
                }
                .frame(height: 180)
                .animation(.easeOut(duration: 0.7), value: animateChart)

                // Legend
                if topCategories.count > 1 {
                    chartLegend
                }
            }
        }
        .cardStyle()
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                animateChart = true
            }
        }
        .onChange(of: selectedCategory) { _, _ in
            animateChart = false
            withAnimation(.easeOut(duration: 0.6).delay(0.05)) {
                animateChart = true
            }
        }
    }

    private var chartLegend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                ForEach(topCategories, id: \.self) { slug in
                    let cat = CategoryEntity.find(slug: slug)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(cat.color)
                            .frame(width: 8, height: 8)
                        Text(cat.name)
                            .font(.micro)
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    .background(cat.color.opacity(0.1))
                    .cornerRadius(20)
                }
            }
        }
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: Spacing.sm) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 32))
                    .foregroundColor(.textSecondary.opacity(0.4))
                Text("Not enough data for trends")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            .padding(.vertical, Spacing.xl)
            Spacer()
        }
        .frame(height: 180)
    }

    private func formatYLabel(_ amount: Double) -> String {
        if amount >= 100_000 { return "₹\(Int(amount / 100_000))L" }
        if amount >= 1_000 { return "₹\(Int(amount / 1_000))K" }
        return "₹\(Int(amount))"
    }
}
