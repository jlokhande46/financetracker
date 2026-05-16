import SwiftUI

struct BudgetsView: View {

    @State var viewModel: BudgetsViewModel
    @State private var goalsViewModel: GoalsViewModel?
    @State private var appearAnimation = false
    @State private var budgetToDelete: BudgetEntity?
    @State private var showDeleteConfirm = false

    @Environment(\.appContainer) private var container

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Color.bgPrimary.ignoresSafeArea()

                Group {
                    if viewModel.isLoading {
                        loadingState
                    } else if viewModel.budgets.isEmpty && (goalsViewModel?.goals.isEmpty ?? true) {
                        emptyState
                    } else {
                        budgetList
                    }
                }

                // FAB
                if !viewModel.budgets.isEmpty || !(goalsViewModel?.goals.isEmpty ?? true) {
                    addButton
                        .padding(Spacing.xl)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await viewModel.load()
                if goalsViewModel == nil, let c = container {
                    goalsViewModel = GoalsViewModel(repo: c.goalRepo)
                }
                goalsViewModel?.load()
            }
            .sheet(isPresented: Binding(
                get: { viewModel.showCreateSheet },
                set: { viewModel.showCreateSheet = $0 }
            )) {
                CreateBudgetSheet(viewModel: viewModel)
            }
            .confirmationDialog(
                "Delete Budget",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let budget = budgetToDelete {
                        withAnimation(.springy) {
                            viewModel.deleteBudget(id: budget.id)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let budget = budgetToDelete {
                    let cat = CategoryEntity.find(slug: budget.categorySlug)
                    Text("Delete budget for \(cat.name)?")
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) {
                    appearAnimation = true
                }
            }
        }
    }

    // MARK: - Budget List
    private var budgetList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: Spacing.lg) {
                // Header navigation bar style
                headerSection
                    .padding(.horizontal, Spacing.base)

                // Summary strip
                summaryStrip
                    .padding(.horizontal, Spacing.base)

                // Budget cards
                if !viewModel.budgetsWithSpend.isEmpty {
                    VStack(spacing: Spacing.md) {
                        ForEach(Array(viewModel.budgetsWithSpend.enumerated()), id: \.element.id) { idx, budget in
                            BudgetCard(budget: budget)
                                .padding(.horizontal, Spacing.base)
                                .opacity(appearAnimation ? 1 : 0)
                                .offset(y: appearAnimation ? 0 : 30)
                                .animation(.easeOut(duration: 0.4).delay(Double(idx) * 0.06), value: appearAnimation)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        budgetToDelete = budget
                                        showDeleteConfirm = true
                                    } label: {
                                        Label("Delete Budget", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }

                // Goals section
                if let gvm = goalsViewModel {
                    goalsSection(gvm)
                }

                Spacer(minLength: 100)
            }
            .padding(.bottom, 20)
        }
        .sheet(isPresented: Binding(
            get: { goalsViewModel?.showAddSheet ?? false },
            set: { goalsViewModel?.showAddSheet = $0 }
        )) {
            AddGoalView(existingGoal: goalsViewModel?.editingGoal) { saved in
                goalsViewModel?.save(saved)
                goalsViewModel?.editingGoal = nil
            }
        }
        .sheet(item: Binding(
            get: { goalsViewModel?.contributionGoal },
            set: { goalsViewModel?.contributionGoal = $0 }
        )) { goal in
            AddContributionSheet(goal: goal) { amount in
                goalsViewModel?.addContribution(goalId: goal.id, amount: amount)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Goals Section

    @ViewBuilder
    private func goalsSection(_ gvm: GoalsViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Goals")
                        .font(.titleLarge)
                        .foregroundColor(.textPrimary)
                    Text("Save for what matters")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                Button {
                    gvm.editingGoal = nil
                    gvm.showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.brandPrimary)
                        .frame(width: 32, height: 32)
                        .background(Color.brandPrimary.opacity(0.15))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, Spacing.base)
            .padding(.top, Spacing.lg)

            if gvm.goals.isEmpty {
                Button {
                    gvm.editingGoal = nil
                    gvm.showAddSheet = true
                } label: {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "target")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.brandPrimary)
                        Text("Create your first goal")
                            .font(.titleMedium)
                            .foregroundStyle(Color.textPrimary)
                        Text("Travel, home, car, emergency fund...")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Spacing.xl)
                    .background(Color.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .strokeBorder(Color.brandPrimary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Spacing.base)
            } else {
                VStack(spacing: Spacing.md) {
                    ForEach(gvm.goals) { goal in
                        GoalCard(
                            goal: goal,
                            onTap: {
                                gvm.editingGoal = goal
                                gvm.showAddSheet = true
                            },
                            onAddContribution: {
                                gvm.contributionGoal = goal
                            }
                        )
                        .padding(.horizontal, Spacing.base)
                        .contextMenu {
                            Button(role: .destructive) {
                                gvm.delete(goal.id)
                            } label: {
                                Label("Delete Goal", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Budgets")
                    .font(.displayMedium)
                    .foregroundColor(.textPrimary)
                Text(Date().monthYear)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            Button(action: { viewModel.showCreateSheet = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.brandPrimary)
                    .frame(width: 36, height: 36)
                    .background(Color.brandPrimary.opacity(0.15))
                    .clipShape(Circle())
            }
        }
        .padding(.top, Spacing.md)
    }

    // MARK: - Summary Strip
    private var summaryStrip: some View {
        HStack(spacing: Spacing.md) {
            summaryChip(
                label: "Budgeted",
                value: viewModel.totalBudgeted.compactString,
                color: .brandPrimary,
                icon: "chart.bar.fill"
            )
            summaryChip(
                label: "Spent",
                value: viewModel.totalSpent.compactString,
                color: .expenseRed,
                icon: "arrow.up.circle.fill"
            )

            if viewModel.overBudgetCount > 0 {
                summaryChip(
                    label: "Over budget",
                    value: "\(viewModel.overBudgetCount)",
                    color: .expenseRed,
                    icon: "exclamationmark.circle.fill"
                )
            } else if viewModel.warningCount > 0 {
                summaryChip(
                    label: "Near limit",
                    value: "\(viewModel.warningCount)",
                    color: .warningAmber,
                    icon: "exclamationmark.triangle.fill"
                )
            }
        }
    }

    private func summaryChip(label: String, value: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.micro)
                    .foregroundColor(.textSecondary)
                Text(value.hasPrefix("₹") ? value : "₹\(value)")
                    .font(Font.amount(14))
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Color.bgCard)
        .cornerRadius(Radius.md)
    }

    // MARK: - FAB
    private var addButton: some View {
        Button(action: { viewModel.showCreateSheet = true }) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                Text("Add Budget")
                    .font(.bodyMedium)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(Color.brandPrimary)
            .clipShape(Capsule())
            .shadow(color: .brandPrimary.opacity(0.4), radius: 12, x: 0, y: 6)
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            VStack(spacing: Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(Color.brandPrimary.opacity(0.12))
                        .frame(width: 100, height: 100)
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 40))
                        .foregroundColor(.brandPrimary)
                }

                VStack(spacing: Spacing.sm) {
                    Text("No budgets yet")
                        .font(.titleLarge)
                        .foregroundColor(.textPrimary)

                    Text("Set spending limits for categories\nto stay on track with your finances.")
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button(action: { viewModel.showCreateSheet = true }) {
                    Text("Set Your First Budget")
                        .font(.titleMedium)
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.vertical, Spacing.md)
                        .background(Color.brandPrimary)
                        .cornerRadius(Radius.xl)
                        .shadow(color: .brandPrimary.opacity(0.4), radius: 12, x: 0, y: 6)
                }
                .padding(.top, Spacing.sm)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.xxl)
    }

    // MARK: - Loading
    private var loadingState: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .fill(Color.bgCard)
                        .frame(maxWidth: .infinity)
                        .frame(height: 110)
                        .padding(.horizontal, Spacing.base)
                }
            }
            .padding(.top, Spacing.xl)
        }
    }
}

