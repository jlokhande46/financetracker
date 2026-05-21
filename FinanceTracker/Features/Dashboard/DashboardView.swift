import SwiftUI
import Charts

struct DashboardView: View {

    @State var viewModel: DashboardViewModel
    @State private var appearAnimation = false
    @State private var showQuickReview = false
    @State private var selectedAccount: AccountEntity? = nil
    @State private var showAllMerchants = false
    @AppStorage("hideAmounts") private var hideAmounts: Bool = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: Spacing.lg) {
                        monthNavigationHeader
                            .padding(.horizontal, Spacing.base)

                        if viewModel.isLoading {
                            loadingPlaceholder
                        } else {
                            contentStack
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
            .sheet(isPresented: $showQuickReview) {
                QuickReviewSheet(
                    transactions: viewModel.pendingReviewTransactions,
                    onConfirm: { txn, newName, newSlug, newTags, rememberName, rememberCategory, applyToPast in
                        viewModel.confirmReview(
                            transaction: txn,
                            newName: newName,
                            newSlug: newSlug,
                            newTags: newTags,
                            rememberName: rememberName,
                            rememberCategory: rememberCategory,
                            applyToPast: applyToPast
                        )
                    },
                    onSkip: { _ in },
                    onDelete: { txn in viewModel.deleteTransaction(txn.id) }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .onDisappear { Task { await viewModel.load() } }
            }
            .sheet(item: $selectedAccount) { acc in
                AccountDetailView(account: acc)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showAllMerchants) {
                if let analysis = viewModel.analysis {
                    AllMerchantsSheet(merchants: analysis.topMerchants)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
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

                Text("Finance Overview")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            // Privacy toggle — masks every amount on this tab. The persisted
            // @AppStorage("hideAmounts") is read by each card directly so the
            // change propagates without re-plumbing state through view models.
            Button(action: {
                withAnimation(.springy) { hideAmounts.toggle() }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }) {
                Image(systemName: hideAmounts ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(hideAmounts ? .warningAmber : .textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.bgCard)
                    .clipShape(Circle())
            }

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

    // MARK: - Main Content
    @ViewBuilder
    private var contentStack: some View {
        if let analysis = viewModel.analysis {
            Group {
                // Hero spending card
                SpendingSummaryCard(analysis: analysis)
                    .padding(.horizontal, Spacing.base)
                    .opacity(appearAnimation ? 1 : 0)
                    .offset(y: appearAnimation ? 0 : 20)
                    .animation(.easeOut(duration: 0.4).delay(0.05), value: appearAnimation)

                // Pending review banner
                if viewModel.pendingReviewCount > 0 {
                    pendingReviewBanner
                        .padding(.horizontal, Spacing.base)
                        .opacity(appearAnimation ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.1), value: appearAnimation)
                }

                // Insights horizontal scroll
                if !viewModel.visibleInsights.isEmpty {
                    insightsSection
                        .opacity(appearAnimation ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.15), value: appearAnimation)
                }

                // Smart heuristic insights (goal projections + want-cut suggestions)
                if !viewModel.smartInsights.isEmpty {
                    SmartInsightsCard(insights: viewModel.smartInsights)
                        .opacity(appearAnimation ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.18), value: appearAnimation)
                }

                // Category Breakdown Chart
                CategoryBreakdownChart(breakdown: analysis.categoryBreakdown)
                    .padding(.horizontal, Spacing.base)
                    .opacity(appearAnimation ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.2), value: appearAnimation)

                // Cash Flow Chart
                CashFlowChart(dayWiseSpend: analysis.dayWiseSpend)
                    .padding(.horizontal, Spacing.base)
                    .opacity(appearAnimation ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.25), value: appearAnimation)

                // Top Merchants
                TopMerchantsCard(merchants: analysis.topMerchants, onViewAll: { showAllMerchants = true })
                    .padding(.horizontal, Spacing.base)
                    .opacity(appearAnimation ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.3), value: appearAnimation)

                // Subscriptions
                if !analysis.subscriptions.isEmpty {
                    SubscriptionSummaryCard(subscriptions: analysis.subscriptions)
                        .padding(.horizontal, Spacing.base)
                        .opacity(appearAnimation ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.35), value: appearAnimation)
                }

                // Card due dates
                if !viewModel.upcomingStatements.isEmpty {
                    cardDueSection
                        .opacity(appearAnimation ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.38), value: appearAnimation)
                }

                // Account balances
                accountBalancesSection
                    .opacity(appearAnimation ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.4), value: appearAnimation)
            }
        } else {
            emptyState
        }
    }

    // MARK: - Pending Review Banner
    private var pendingReviewBanner: some View {
        Button(action: { showQuickReview = true }) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.warningAmber.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.warningAmber)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.pendingReviewCount) transactions need review")
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)
                    Text("Low confidence auto-categorizations")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textSecondary)
            }
            .padding(Spacing.base)
            .background(Color.warningAmber.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(Color.warningAmber.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(Radius.lg)
        }
    }

    // MARK: - Insights Section
    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("INSIGHTS")
                .font(.micro)
                .fontWeight(.semibold)
                .foregroundColor(.textSecondary)
                .kerning(1.2)
                .padding(.horizontal, Spacing.base)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(Array(viewModel.visibleInsights.enumerated()), id: \.element.id) { idx, insight in
                        InsightCard(insight: insight) {
                            // Persist dismissal so reload doesn't bring it back.
                            withAnimation(.springy) {
                                viewModel.dismissInsight(insight.id)
                            }
                        }
                        .opacity(appearAnimation ? 1 : 0)
                        .animation(.easeOut(duration: 0.3).delay(0.15 + Double(idx) * 0.05), value: appearAnimation)
                    }
                }
                .padding(.horizontal, Spacing.base)
            }
        }
    }

    // MARK: - Card Due Dates

    private var cardDueSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("CARD PAYMENTS DUE")
                    .font(.micro)
                    .fontWeight(.semibold)
                    .foregroundColor(.textSecondary)
                    .kerning(1.2)
                Spacer()
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.warningAmber)
            }
            .padding(.horizontal, Spacing.base)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(viewModel.upcomingStatements) { stmt in
                        CardDueCard(statement: stmt) {
                            viewModel.markStatementPaid(stmt.id)
                        }
                    }
                }
                .padding(.horizontal, Spacing.base)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Account Balances
    private var accountBalancesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("ACCOUNTS")
                .font(.micro)
                .fontWeight(.semibold)
                .foregroundColor(.textSecondary)
                .kerning(1.2)
                .padding(.horizontal, Spacing.base)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(viewModel.accounts.filter(\.isActive)) { account in
                        Button { selectedAccount = account } label: {
                            AccountBalanceChip(account: account)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.base)
            }
        }
    }

    // MARK: - Loading Placeholder
    private var loadingPlaceholder: some View {
        VStack(spacing: Spacing.lg) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(Color.bgCard)
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .redacted(reason: .placeholder)
                    .shimmering()
                    .padding(.horizontal, Spacing.base)
            }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Spacer(minLength: 60)
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 56))
                .foregroundColor(.textSecondary.opacity(0.4))
            Text("No data for this month")
                .font(.titleLarge)
                .foregroundColor(.textPrimary)
            Text("Add transactions or switch to a different month")
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

// MARK: - Account Balance Chip
private struct AccountBalanceChip: View {
    let account: AccountEntity
    @AppStorage("hideAmounts") private var hideAmounts: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: account.type.icon)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: account.colorHex))

                Text(account.type.displayName)
                    .font(.micro)
                    .foregroundColor(.textSecondary)
            }

            Text(account.name)
                .font(.bodyMedium)
                .fontWeight(.semibold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            Text(account.balance.currencyString(hidden: hideAmounts))
                .font(Font.amount(16))
                .foregroundColor(.textPrimary)
                .contentTransition(.numericText())

            if let pct = account.utilizationPercent, account.type == .credit {
                ProgressView(value: min(pct / 100, 1.0))
                    .tint(utilizationColor(pct))
                    .frame(width: 120)
            }
        }
        .padding(Spacing.md)
        .frame(width: 150, alignment: .leading)
        .background(Color.bgCard)
        .cornerRadius(Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color(hex: account.colorHex).opacity(0.25), lineWidth: 1)
        )
    }

    private func utilizationColor(_ pct: Double) -> Color {
        if pct < 30 { return .incomeGreen }
        if pct < 70 { return .warningAmber }
        return .expenseRed
    }
}

// MARK: - Shimmer modifier (simple placeholder)
private struct ShimmeringModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .white.opacity(0.06), .clear]),
                    startPoint: .init(x: phase, y: 0),
                    endPoint: .init(x: phase + 1, y: 0)
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 1.5
                    }
                }
            )
            .clipped()
    }
}

private extension View {
    func shimmering() -> some View {
        modifier(ShimmeringModifier())
    }
}

