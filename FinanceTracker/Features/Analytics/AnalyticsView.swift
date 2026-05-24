import SwiftUI
import Charts

struct AnalyticsView: View {

    @State var viewModel: AnalyticsViewModel
    @State private var appearAnimation = false
    @State private var showManageInvestments = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: Spacing.lg) {
                        monthNavigationHeader
                            .padding(.horizontal, Spacing.base)

                        if viewModel.isLoading {
                            loadingPlaceholder
                        } else if let analysis = viewModel.analysis {
                            // Net Worth — always at the top
                            if let nw = viewModel.netWorthSnapshot {
                                NetWorthCard(
                                    snapshot: nw,
                                    history: viewModel.netWorthHistory,
                                    onManageInvestments: { showManageInvestments = true }
                                )
                                .padding(.horizontal, Spacing.base)
                            }

                            summaryNumbers(analysis)
                                .padding(.horizontal, Spacing.base)

                            NeedsWantsCard(breakdown: viewModel.needsWantsBreakdown)
                                .padding(.horizontal, Spacing.base)

                            CategoryTrendChart(
                                last6Months: viewModel.last6MonthsData,
                                selectedCategory: viewModel.selectedCategory
                            )
                            .padding(.horizontal, Spacing.base)

                            categoryBreakdownList(analysis)
                                .padding(.horizontal, Spacing.base)

                            MonthlyComparisonCard(
                                current: analysis,
                                previous: viewModel.last6MonthsData.dropLast().last
                            )
                            .padding(.horizontal, Spacing.base)

                            topMerchantsSection(analysis)
                                .padding(.horizontal, Spacing.base)

                            if !analysis.subscriptions.isEmpty {
                                subscriptionWasteSection(analysis)
                                    .padding(.horizontal, Spacing.base)
                            }

                            // Monthly Report Card
                            MonthlyReportCard(
                                analysis: analysis,
                                budgetAdherence: viewModel.budgetAdherenceRate,
                                billsPaidOnTime: viewModel.billsPaidOnTimeRate
                            )
                            .padding(.horizontal, Spacing.base)

                            // What-If Investment Simulator
                            WhatIfSimulatorCard(
                                monthlyWantsSpend: viewModel.monthlyWantsSpend
                            )
                            .padding(.horizontal, Spacing.base)
                        } else {
                            emptyState
                        }
                    }
                    .padding(.bottom, 100)
                }
                .refreshable {
                    await viewModel.load()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await viewModel.load() }
            .sheet(isPresented: $showManageInvestments) {
                ManageInvestmentsSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .onDisappear { Task { await viewModel.load() } }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) {
                    appearAnimation = true
                }
            }
        }
    }

    // MARK: - Month Header
    private var monthNavigationHeader: some View {
        HStack(spacing: Spacing.md) {
            Button(action: { viewModel.selectMonth(previousMonth) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.bgCard)
                    .clipShape(Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.selectedMonth.monthYear.uppercased())
                    .font(.titleMedium)
                    .foregroundColor(.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.springy, value: viewModel.selectedMonth)

                Text("Analytics")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            Button(action: { viewModel.selectMonth(nextMonth) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isCurrentMonth ? .textSecondary.opacity(0.3) : .textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.bgCard)
                    .clipShape(Circle())
            }
            .disabled(isCurrentMonth)
        }
        .padding(.top, Spacing.md)
    }

    // MARK: - Summary Numbers
    private func summaryNumbers(_ analysis: MonthlyAnalysis) -> some View {
        HStack(spacing: Spacing.md) {
            summaryTile(
                label: "Income",
                value: analysis.totalIncome.compactString,
                color: .incomeGreen,
                icon: "arrow.down.circle.fill"
            )
            summaryTile(
                label: "Expenses",
                value: analysis.totalExpenses.compactString,
                color: .expenseRed,
                icon: "arrow.up.circle.fill"
            )
            summaryTile(
                label: "Savings",
                value: analysis.savings.compactString,
                color: analysis.savings >= 0 ? .incomeGreen : .expenseRed,
                icon: "banknote.fill"
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "percent")
                        .font(.system(size: 11))
                        .foregroundColor(.brandPrimary)
                    Text("Rate")
                        .font(.micro)
                        .foregroundColor(.textSecondary)
                }
                Text(String(format: "%.0f%%", abs(analysis.savingsRate)))
                    .font(Font.amount(18))
                    .fontWeight(.bold)
                    .foregroundColor(.brandPrimary)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.md)
            .background(Color.bgCard)
            .cornerRadius(Radius.md)
        }
    }

    private func summaryTile(label: String, value: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
                Text(label)
                    .font(.micro)
                    .foregroundColor(.textSecondary)
            }
            Text("₹\(value)")
                .font(Font.amount(16))
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Color.bgCard)
        .cornerRadius(Radius.md)
    }

    // MARK: - Category Breakdown List
    private func categoryBreakdownList(_ analysis: MonthlyAnalysis) -> some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            Text("CATEGORY BREAKDOWN")
                .font(.micro)
                .fontWeight(.semibold)
                .foregroundColor(.textSecondary)
                .kerning(1.2)

            VStack(spacing: Spacing.sm) {
                ForEach(analysis.categoryBreakdown) { item in
                    let cat = CategoryEntity.find(slug: item.categorySlug)
                    let isSelected = viewModel.selectedCategory == item.categorySlug

                    Button(action: { viewModel.selectCategory(item.categorySlug) }) {
                        HStack(spacing: Spacing.md) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(cat.color.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                Image(systemName: cat.icon)
                                    .font(.system(size: 16))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(cat.name)
                                        .font(.bodyMedium)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.textPrimary)
                                    Spacer()
                                    Text(item.amount.currencyString)
                                        .font(Font.amount(14))
                                        .fontWeight(.semibold)
                                        .foregroundColor(.textPrimary)
                                }

                                HStack(spacing: Spacing.sm) {
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color.white.opacity(0.07))
                                                .frame(height: 4)
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(cat.color.opacity(0.8))
                                                .frame(width: geo.size.width * (item.percent / 100), height: 4)
                                        }
                                    }
                                    .frame(height: 4)

                                    Text(String(format: "%.0f%%", item.percent))
                                        .font(.micro)
                                        .foregroundColor(.textSecondary)
                                        .frame(width: 32, alignment: .trailing)

                                    Text("\(item.count) txns")
                                        .font(.micro)
                                        .foregroundColor(.textSecondary)
                                }
                            }
                        }
                        .padding(Spacing.md)
                        .background(
                            isSelected
                                ? cat.color.opacity(0.08)
                                : Color.bgCard
                        )
                        .cornerRadius(Radius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md)
                                .strokeBorder(
                                    isSelected ? cat.color.opacity(0.4) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(.springy, value: isSelected)
                }
            }
        }
        .padding(Spacing.base)
        .background(Color.bgCard)
        .cornerRadius(Radius.lg)
    }

    // MARK: - Top Merchants Section
    private func topMerchantsSection(_ analysis: MonthlyAnalysis) -> some View {
        TopMerchantsCard(merchants: analysis.topMerchants)
    }

    // MARK: - Subscription Waste
    private func subscriptionWasteSection(_ analysis: MonthlyAnalysis) -> some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SUBSCRIPTION REVIEW")
                        .font(.micro)
                        .fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                        .kerning(1.2)
                    Text("Consider cancelling")
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)
                }
                Spacer()
                Text("\(analysis.subscriptions.count) active")
                    .font(.caption)
                    .foregroundColor(.warningAmber)
            }

            VStack(spacing: Spacing.sm) {
                ForEach(analysis.subscriptions) { sub in
                    let cat = CategoryEntity.find(slug: sub.categorySlug)
                    HStack(spacing: Spacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(cat.color.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: cat.icon)
                                .font(.system(size: 16))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(sub.merchantName)
                                .font(.bodyMedium)
                                .fontWeight(.semibold)
                                .foregroundColor(.textPrimary)
                            Text("Monthly · Auto-renewing")
                                .font(.micro)
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        Text(sub.amount.currencyString)
                            .font(Font.amount(14))
                            .fontWeight(.semibold)
                            .foregroundColor(.expenseRed)
                    }
                    .padding(Spacing.sm)
                    .background(Color.bgElevated)
                    .cornerRadius(Radius.md)
                }
            }

            let total = analysis.subscriptions.reduce(Decimal(0)) { $0 + $1.amount }
            HStack {
                Text("Annual cost")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                Spacer()
                Text((total * 12).currencyString)
                    .font(Font.amount(15))
                    .fontWeight(.bold)
                    .foregroundColor(.expenseRed)
            }
            .padding(Spacing.md)
            .background(Color.expenseRed.opacity(0.08))
            .cornerRadius(Radius.md)
        }
        .cardStyle()
    }

    // MARK: - Loading / Empty
    private var loadingPlaceholder: some View {
        VStack(spacing: Spacing.lg) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(Color.bgCard)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .padding(.horizontal, Spacing.base)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Spacer(minLength: 60)
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 56))
                .foregroundColor(.textSecondary.opacity(0.4))
            Text("No analytics data")
                .font(.titleLarge)
                .foregroundColor(.textPrimary)
            Text("Add transactions to see spending insights")
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Spacing.xl)
    }

    // MARK: - Computed
    private var isCurrentMonth: Bool {
        Calendar.current.isDate(viewModel.selectedMonth, equalTo: Date(), toGranularity: .month)
    }

    private var previousMonth: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: viewModel.selectedMonth) ?? viewModel.selectedMonth
    }

    private var nextMonth: Date {
        Calendar.current.date(byAdding: .month, value: 1, to: viewModel.selectedMonth) ?? viewModel.selectedMonth
    }
}

// Helper refresh method
private extension AnalyticsViewModel {
    func refreshData() {
        Task { await load() }
    }
}

