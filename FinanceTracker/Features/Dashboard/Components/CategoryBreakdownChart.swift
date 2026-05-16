import SwiftUI
import Charts

struct CategoryBreakdownChart: View {

    let breakdown: [CategorySpend]
    @State private var selectedSlug: String?
    @State private var animateChart = false

    private var displayData: [CategorySpend] {
        Array(breakdown.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SPENDING BY CATEGORY")
                        .font(.micro)
                        .fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                        .kerning(1.2)
                    Text("This Month")
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)
                }
                Spacer()
                Text("\(breakdown.count) categories")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            if displayData.isEmpty {
                emptyChartState
            } else {
                HStack(alignment: .center, spacing: Spacing.xl) {
                    // Donut Chart
                    ZStack {
                        Chart(displayData) { item in
                            let cat = CategoryEntity.find(slug: item.categorySlug)
                            SectorMark(
                                angle: .value("Amount", animateChart ? Double(truncating: item.amount as NSDecimalNumber) : 0),
                                innerRadius: .ratio(0.58),
                                angularInset: 2
                            )
                            .foregroundStyle(
                                selectedSlug == nil || selectedSlug == item.categorySlug
                                    ? cat.color
                                    : cat.color.opacity(0.25)
                            )
                            .cornerRadius(4)
                        }
                        .animation(.easeOut(duration: 0.7), value: animateChart)
                        .chartLegend(.hidden)

                        // Center label
                        if let slug = selectedSlug,
                           let item = displayData.first(where: { $0.categorySlug == slug }) {
                            let cat = CategoryEntity.find(slug: slug)
                            VStack(spacing: 2) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 20))
                                Text(item.amount.compactString)
                                    .font(Font.amount(13))
                                    .fontWeight(.bold)
                                    .foregroundColor(.textPrimary)
                                Text(String(format: "%.0f%%", item.percent))
                                    .font(.micro)
                                    .foregroundColor(.textSecondary)
                            }
                        } else {
                            VStack(spacing: 2) {
                                Text("💸")
                                    .font(.system(size: 20))
                                Text("Total")
                                    .font(.micro)
                                    .foregroundColor(.textSecondary)
                            }
                        }
                    }
                    .frame(width: 130, height: 130)

                    // Legend
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(displayData) { item in
                            legendRow(for: item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .cardStyle()
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                animateChart = true
            }
        }
    }

    private func legendRow(for item: CategorySpend) -> some View {
        let cat = CategoryEntity.find(slug: item.categorySlug)
        let isSelected = selectedSlug == item.categorySlug

        return Button(action: {
            withAnimation(.springy) {
                selectedSlug = selectedSlug == item.categorySlug ? nil : item.categorySlug
            }
        }) {
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(cat.color)
                    .frame(width: 8, height: 8)

                Text(cat.name)
                    .font(.caption)
                    .foregroundColor(isSelected ? .textPrimary : .textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 0) {
                    Text(item.amount.compactString)
                        .font(Font.amount(12))
                        .foregroundColor(isSelected ? .textPrimary : .textSecondary)
                    Text(String(format: "%.0f%%", item.percent))
                        .font(.micro)
                        .foregroundColor(.textSecondary.opacity(0.7))
                }
            }
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? cat.color.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyChartState: some View {
        HStack {
            Spacer()
            VStack(spacing: Spacing.sm) {
                Image(systemName: "chart.pie")
                    .font(.system(size: 32))
                    .foregroundColor(.textSecondary.opacity(0.4))
                Text("No spending data")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
            }
            .padding(.vertical, Spacing.xl)
            Spacer()
        }
    }
}

#Preview {
    CategoryBreakdownChart(breakdown: [
        CategorySpend(categorySlug: "food", amount: 12400, count: 18, percent: 32),
        CategorySpend(categorySlug: "transport", amount: 8200, count: 22, percent: 21),
        CategorySpend(categorySlug: "shopping", amount: 6500, count: 8, percent: 17),
        CategorySpend(categorySlug: "entertainment", amount: 4100, count: 6, percent: 11),
        CategorySpend(categorySlug: "utilities", amount: 3800, count: 4, percent: 10),
        CategorySpend(categorySlug: "health", amount: 3200, count: 3, percent: 9),
    ])
    .padding()
    .background(Color.bgPrimary)
}
