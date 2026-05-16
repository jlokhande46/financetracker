import SwiftUI

enum DateRangePreset: String, CaseIterable {
    case thisMonth    = "This Month"
    case lastMonth    = "Last Month"
    case last3Months  = "Last 3 Months"
    case custom       = "Custom"
}

struct TransactionFilterSheet: View {
    @Binding var selectedType: TransactionType?
    @Binding var selectedCategory: String?
    @Binding var selectedSource: TransactionSource?

    var onApply: () -> Void

    @State private var localType: TransactionType? = nil
    @State private var localCategory: String? = nil
    @State private var localSource: TransactionSource? = nil
    @State private var selectedDateRange: DateRangePreset = .thisMonth
    @State private var minAmount: Double = 0
    @State private var maxAmount: Double = 100_000
    @State private var amountRange: ClosedRange<Double> = 0...100_000
    @Environment(\.dismiss) private var dismiss

    private var activeFilterCount: Int {
        var count = 0
        if localType != nil { count += 1 }
        if localCategory != nil { count += 1 }
        if localSource != nil { count += 1 }
        if selectedDateRange != .thisMonth { count += 1 }
        return count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.xl) {

                        // Type Section
                        FilterSection(title: "Transaction Type") {
                            HStack(spacing: Spacing.sm) {
                                TypePill(label: "All", isSelected: localType == nil) {
                                    withAnimation(.springy) { localType = nil }
                                }
                                TypePill(label: "Expense", isSelected: localType == .debit) {
                                    withAnimation(.springy) { localType = .debit }
                                }
                                TypePill(label: "Income", isSelected: localType == .credit) {
                                    withAnimation(.springy) { localType = .credit }
                                }
                                Spacer()
                            }
                        }

                        // Category Section
                        FilterSection(title: "Category") {
                            FlowLayout(spacing: Spacing.sm) {
                                ForEach(CategoryEntity.system) { cat in
                                    CategoryFilterChip(
                                        category: cat,
                                        isSelected: localCategory == cat.slug
                                    ) {
                                        withAnimation(.springy) {
                                            if localCategory == cat.slug {
                                                localCategory = nil
                                            } else {
                                                localCategory = cat.slug
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Source Section
                        FilterSection(title: "Source") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Spacing.sm) {
                                    SourcePill(label: "All", isSelected: localSource == nil) {
                                        withAnimation(.springy) { localSource = nil }
                                    }
                                    ForEach(TransactionSource.allCases, id: \.self) { source in
                                        SourcePill(label: source.displayName, isSelected: localSource == source) {
                                            withAnimation(.springy) {
                                                localSource = localSource == source ? nil : source
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Date Range Section
                        FilterSection(title: "Date Range") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Spacing.sm) {
                                    ForEach(DateRangePreset.allCases, id: \.self) { preset in
                                        DateRangePill(preset: preset, isSelected: selectedDateRange == preset) {
                                            withAnimation(.springy) { selectedDateRange = preset }
                                        }
                                    }
                                }
                            }
                        }

                        // Amount Range Section
                        FilterSection(title: "Amount Range") {
                            VStack(spacing: Spacing.md) {
                                HStack {
                                    AmountBound(label: "Min", value: minAmount)
                                    Spacer()
                                    AmountBound(label: "Max", value: maxAmount >= 100_000 ? nil : maxAmount)
                                }

                                RangeSliderView(
                                    minValue: $minAmount,
                                    maxValue: $maxAmount,
                                    range: 0...100_000
                                )
                            }
                        }

                        Spacer(minLength: Spacing.xxl)
                    }
                    .padding(.horizontal, Spacing.base)
                    .padding(.top, Spacing.base)
                    .padding(.bottom, 100)
                }

                // Apply button pinned to bottom
                VStack {
                    Spacer()
                    Button {
                        selectedType = localType
                        selectedCategory = localCategory
                        selectedSource = localSource
                        onApply()
                        dismiss()
                    } label: {
                        HStack {
                            Text("Apply Filters")
                                .font(.titleMedium)
                                .foregroundStyle(.white)

                            if activeFilterCount > 0 {
                                Text("\(activeFilterCount)")
                                    .font(.micro)
                                    .foregroundStyle(Color.brandPrimary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.white)
                                    .clipShape(Capsule())
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.base)
                        .background(Color.brandPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.full))
                        .padding(.horizontal, Spacing.base)
                        .padding(.bottom, Spacing.xl)
                    }
                    .background(
                        Color.bgPrimary
                            .shadow(color: .black.opacity(0.4), radius: 20, y: -10)
                    )
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Clear All") {
                        withAnimation(.springy) {
                            localType = nil
                            localCategory = nil
                            localSource = nil
                            selectedDateRange = .thisMonth
                            minAmount = 0
                            maxAmount = 100_000
                        }
                    }
                    .foregroundStyle(activeFilterCount > 0 ? Color.expenseRed : Color.textTertiary)
                    .disabled(activeFilterCount == 0)
                }
            }
            .onAppear {
                localType = selectedType
                localCategory = selectedCategory
                localSource = selectedSource
            }
        }
    }
}

// MARK: - Filter Section
private struct FilterSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)

            content()
        }
    }
}

// MARK: - Pill Buttons
private struct TypePill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.bodyMedium)
                .foregroundStyle(isSelected ? .white : Color.textSecondary)
                .padding(.horizontal, Spacing.base)
                .padding(.vertical, Spacing.sm)
                .background(isSelected ? Color.brandPrimary : Color.bgCard)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.springy, value: isSelected)
    }
}

private struct SourcePill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.bodyMedium)
                .foregroundStyle(isSelected ? .white : Color.textSecondary)
                .padding(.horizontal, Spacing.base)
                .padding(.vertical, Spacing.sm)
                .background(isSelected ? Color.brandPrimary : Color.bgCard)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.springy, value: isSelected)
    }
}

private struct DateRangePill: View {
    let preset: DateRangePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(preset.rawValue)
                .font(.bodyMedium)
                .foregroundStyle(isSelected ? .white : Color.textSecondary)
                .padding(.horizontal, Spacing.base)
                .padding(.vertical, Spacing.sm)
                .background(isSelected ? Color.brandPrimary : Color.bgCard)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.springy, value: isSelected)
    }
}

// MARK: - Category Filter Chip
private struct CategoryFilterChip: View {
    let category: CategoryEntity
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? .white : category.color)

                Text(category.name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white : Color.textSecondary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(isSelected ? Color.brandPrimary : Color.bgCard)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.springy, value: isSelected)
    }
}

// MARK: - Amount Bound Display
private struct AmountBound: View {
    let label: String
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.micro)
                .foregroundStyle(Color.textTertiary)
            if let v = value {
                Text("₹\(Int(v).formatted())")
                    .font(.amount(15))
                    .foregroundStyle(Color.textPrimary)
            } else {
                Text("Any")
                    .font(.amount(15))
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }
}

// MARK: - Simple Range Slider
private struct RangeSliderView: View {
    @Binding var minValue: Double
    @Binding var maxValue: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Slider(value: $minValue, in: range.lowerBound...min(maxValue - 1000, range.upperBound), step: 500)
                .tint(Color.brandPrimary)

            Slider(value: $maxValue, in: max(minValue + 1000, range.lowerBound)...range.upperBound, step: 500)
                .tint(Color.brandPrimary)
        }
    }
}

// MARK: - Flow Layout
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        height = y + rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

#Preview {
    TransactionFilterSheet(
        selectedType: .constant(nil),
        selectedCategory: .constant(nil),
        selectedSource: .constant(nil),
        onApply: {}
    )
}
