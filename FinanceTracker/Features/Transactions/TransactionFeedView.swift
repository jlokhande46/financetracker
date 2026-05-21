import SwiftUI
import SwiftData

struct TransactionFeedView: View {
    @State private var viewModel: TransactionListViewModel
    @State private var selectedTransaction: TransactionEntity? = nil
    @State private var reviewTransaction: TransactionEntity? = nil
    @State private var showSMSImport: Bool = false
    @State private var showQuickReview: Bool = false
    @State private var showBulkToast: Bool = false
    @State private var bulkToastMessage: String = ""

    init(transactionRepo: TransactionRepositoryImpl, accountRepo: AccountRepositoryImpl? = nil) {
        self._viewModel = State(initialValue: TransactionListViewModel(transactionRepo: transactionRepo, accountRepo: accountRepo))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.brandPrimary)
                        .scaleEffect(1.3)
                } else {
                    mainContent
                }

                // FABs
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: Spacing.md) {
                            // SMS Import FAB
                            Button {
                                showSMSImport = true
                            } label: {
                                Image(systemName: "text.bubble.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(Color.warningAmber)
                                    .clipShape(Circle())
                                    .shadow(color: Color.warningAmber.opacity(0.4), radius: 8, y: 4)
                            }
                            .buttonStyle(.plain)

                            // Add Manually FAB
                            Button {
                                viewModel.showAddSheet = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 56, height: 56)
                                    .background(Color.brandPrimary)
                                    .clipShape(Circle())
                                    .shadow(color: Color.brandPrimary.opacity(0.4), radius: 12, y: 4)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.trailing, Spacing.xl)
                        .padding(.bottom, Spacing.xxl)
                    }
                }
            }
            .navigationTitle("Transactions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        viewModel.showFilterSheet = true
                    } label: {
                        Image(systemName: viewModel.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(viewModel.hasActiveFilters ? Color.brandPrimary : Color.textSecondary)
                    }
                }
            }
            .sheet(isPresented: $showSMSImport) {
                SMSImportView()
                    .onDisappear {
                        Task { await viewModel.load() }
                    }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search transactions, merchants...")
            .refreshable {
                await viewModel.load()
            }
            .task {
                await viewModel.load()
            }
            .sheet(isPresented: $viewModel.showAddSheet) {
                AddTransactionView { newTxn in
                    viewModel.allTransactions.insert(newTxn, at: 0)
                    viewModel.applyFilters()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $viewModel.showFilterSheet) {
                TransactionFilterSheet(
                    selectedType: $viewModel.selectedType,
                    selectedCategory: $viewModel.selectedCategory,
                    selectedSource: $viewModel.selectedSource,
                    selectedTags: $viewModel.selectedTags,
                    availableTags: viewModel.allKnownTags,
                    onApply: { viewModel.applyFilters() }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedTransaction) { txn in
                TransactionDetailView(
                    transaction: txn,
                    onUpdate: { updated in
                        viewModel.updateTransaction(updated)
                    },
                    onDelete: { id in
                        viewModel.deleteTransaction(id: id)
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $reviewTransaction) { txn in
                CategoryReviewSheet(
                    transaction: txn,
                    onConfirm: { slug, _ in
                        viewModel.confirmCategory(transaction: txn, newSlug: slug)
                    },
                    onSkip: {}
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
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
                    onDelete: { txn in
                        viewModel.deleteTransaction(id: txn.id)
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .onDisappear { Task { await viewModel.load() } }
            }
            .onChange(of: viewModel.bulkUpdateMessage) { _, message in
                if let msg = message {
                    bulkToastMessage = msg
                    showBulkToast = true
                    viewModel.bulkUpdateMessage = nil
                }
            }
            .toast(isPresented: $showBulkToast, message: bulkToastMessage, type: .success)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {

                // Filter chips row
                filterChipsRow
                    .padding(.bottom, Spacing.sm)

                // Active filters banner
                if viewModel.hasActiveFilters {
                    activeFiltersBanner
                        .padding(.horizontal, Spacing.base)
                        .padding(.bottom, Spacing.md)
                }

                // Pending review section
                if !viewModel.pendingReviewTransactions.isEmpty && !viewModel.hasActiveFilters && viewModel.searchText.isEmpty {
                    pendingReviewSection
                        .padding(.bottom, Spacing.md)
                }

                // Grouped transactions
                if viewModel.groupedTransactions.isEmpty {
                    EmptyStateView(
                        icon: viewModel.hasActiveFilters || !viewModel.searchText.isEmpty ? "magnifyingglass" : "creditcard",
                        title: viewModel.hasActiveFilters || !viewModel.searchText.isEmpty ? "No results found" : "No transactions yet",
                        subtitle: viewModel.hasActiveFilters || !viewModel.searchText.isEmpty
                            ? "Try adjusting your search or filters"
                            : "Add your first transaction using the + button below",
                        action: viewModel.hasActiveFilters ? { viewModel.clearFilters() } : nil,
                        actionTitle: "Clear Filters"
                    )
                    .padding(.top, Spacing.xxl)
                } else {
                    ForEach(viewModel.groupedTransactions, id: \.key) { group in
                        transactionSection(group: group)
                    }
                    if viewModel.isLoadingMore {
                        HStack(spacing: Spacing.sm) {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(Color.brandPrimary)
                            Text("Loading more…")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.lg)
                    }
                }

                // Bottom padding for FAB
                Color.clear.frame(height: 100)
            }
        }
    }

    // MARK: - Filter Chips

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                FilterQuickChip(
                    label: "All",
                    isSelected: viewModel.selectedCategory == nil && viewModel.selectedType == nil && viewModel.selectedSource == nil
                ) {
                    withAnimation(.springy) { viewModel.clearFilters() }
                }

                // Sort Order
                Menu {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button {
                            withAnimation(.springy) { viewModel.sortOrder = order }
                        } label: {
                            Label(order.rawValue, systemImage: viewModel.sortOrder == order ? "checkmark" : "")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .medium))
                        Text(viewModel.sortOrder.rawValue)
                            .font(.caption)
                    }
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.bgCard)
                    .clipShape(Capsule())
                }

                // Quick category chips (top 5 popular)
                ForEach(["food", "travel", "shopping", "bills", "entertainment"], id: \.self) { slug in
                    let cat = CategoryEntity.find(slug: slug)
                    FilterQuickChip(
                        label: cat.name,
                        icon: cat.icon,
                        color: cat.color,
                        isSelected: viewModel.selectedCategory == slug
                    ) {
                        withAnimation(.springy) {
                            viewModel.selectedCategory = viewModel.selectedCategory == slug ? nil : slug
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Active Filters Banner

    private var activeFiltersBanner: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.brandPrimary)

            Text(activeFiltersDescription)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            Spacer()

            Button {
                withAnimation(.springy) { viewModel.clearFilters() }
            } label: {
                Text("Clear")
                    .font(.caption)
                    .foregroundStyle(Color.brandPrimary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.brandPrimary.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.md)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private var activeFiltersDescription: String {
        var parts: [String] = []
        if let cat = viewModel.selectedCategory {
            parts.append(CategoryEntity.find(slug: cat).name)
        }
        if let type = viewModel.selectedType {
            parts.append(type == .debit ? "Expenses" : "Income")
        }
        if let source = viewModel.selectedSource {
            parts.append(source.displayName)
        }
        if !viewModel.selectedTags.isEmpty {
            parts.append("#" + viewModel.selectedTags.sorted().joined(separator: ", #"))
        }
        return "Filtering by: \(parts.joined(separator: ", "))"
    }

    // MARK: - Pending Review Section

    private var pendingReviewSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                showQuickReview = true
            } label: {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.warningAmber)

                    Text("\(viewModel.pendingReviewTransactions.count) transactions need review")
                        .font(.caption)
                        .foregroundStyle(Color.warningAmber)

                    Spacer()

                    Text("Review all →")
                        .font(.caption)
                        .foregroundStyle(Color.brandPrimary)
                }
                .padding(.horizontal, Spacing.base)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(viewModel.pendingReviewTransactions.prefix(5)) { txn in
                        PendingReviewCard(transaction: txn) {
                            reviewTransaction = txn
                        }
                    }
                }
                .padding(.horizontal, Spacing.base)
            }
        }
    }

    // MARK: - Transaction Section

    private func transactionSection(group: (key: String, transactions: [TransactionEntity])) -> some View {
        Section {
            ForEach(group.transactions) { txn in
                VStack(spacing: 0) {
                    TransactionRowView(
                        transaction: txn,
                        accountChip: viewModel.accountDisplay(for: txn),
                        onTap: { selectedTransaction = txn },
                        onSetIntent: { newIntent in
                            withAnimation { viewModel.setIntentOverride(transaction: txn, intent: newIntent) }
                        },
                        onTapTag: { tag in
                            withAnimation(.springy) {
                                if viewModel.selectedTags.contains(tag) {
                                    viewModel.selectedTags.remove(tag)
                                } else {
                                    viewModel.selectedTags.insert(tag)
                                }
                            }
                        }
                    )
                    .padding(.horizontal, Spacing.base)
                    .onAppear {
                        // Prefetch the next page when one of the last rows of
                        // the currently-loaded set enters view, so the user
                        // never hits an empty scroll.
                        if viewModel.isNearEndOfLoadedSet(txn) {
                            Task { await viewModel.loadMoreIfNeeded() }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation {
                                viewModel.deleteTransaction(id: txn.id)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            reviewTransaction = txn
                        } label: {
                            Label("Review", systemImage: "tag")
                        }
                        .tint(Color.warningAmber)
                    }
                    // Left-edge swipe: tag this transaction as a Need (green) or a Want (amber).
                    // A third button clears any override so the category's default applies.
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            withAnimation { viewModel.setIntentOverride(transaction: txn, intent: .need) }
                        } label: {
                            Label("Need", systemImage: CategoryIntent.need.icon)
                        }
                        .tint(CategoryIntent.need.color)

                        Button {
                            withAnimation { viewModel.setIntentOverride(transaction: txn, intent: .want) }
                        } label: {
                            Label("Want", systemImage: CategoryIntent.want.icon)
                        }
                        .tint(CategoryIntent.want.color)

                        if txn.intentOverride != nil {
                            Button {
                                withAnimation { viewModel.setIntentOverride(transaction: txn, intent: nil) }
                            } label: {
                                Label("Clear", systemImage: "arrow.uturn.backward")
                            }
                            .tint(Color.neutralGray)
                        }
                    }

                    if txn.id != group.transactions.last?.id {
                        Divider()
                            .background(Color.textTertiary.opacity(0.3))
                            .padding(.leading, 76)
                            .padding(.trailing, Spacing.base)
                    }
                }
                .background(Color.bgCard)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .padding(.horizontal, Spacing.base)
            .padding(.bottom, Spacing.md)
        } header: {
            transactionSectionHeader(for: group)
        }
    }

    private func transactionSectionHeader(for group: (key: String, transactions: [TransactionEntity])) -> some View {
        let debitTotal = group.transactions.filter(\.isDebit).reduce(Decimal(0)) { $0 + $1.amount }
        let creditTotal = group.transactions.filter(\.isCredit).reduce(Decimal(0)) { $0 + $1.amount }
        let hasOnlyCredits = debitTotal == 0

        return HStack {
            Text(group.key)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .textCase(nil)

            Spacer()

            if creditTotal > 0 && debitTotal > 0 {
                Text("+\(formattedCompact(creditTotal))")
                    .font(.amount(12))
                    .foregroundStyle(Color.incomeGreen)

                Text("−\(formattedCompact(debitTotal))")
                    .font(.amount(12))
                    .foregroundStyle(Color.textSecondary)
            } else if hasOnlyCredits {
                Text("+\(formattedCompact(creditTotal))")
                    .font(.amount(12))
                    .foregroundStyle(Color.incomeGreen)
            } else {
                Text("−\(formattedCompact(debitTotal))")
                    .font(.amount(12))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.sm)
        .background(Color.bgPrimary)
    }

    private func formattedCompact(_ amount: Decimal) -> String {
        let d = Double(truncating: amount as NSDecimalNumber)
        if d >= 1_00_000 { return String(format: "%.1fL", d / 1_00_000) }
        if d >= 1_000 { return String(format: "%.0fK", d / 1_000) }
        return String(format: "%.0f", d)
    }
}

// MARK: - Quick Filter Chip
private struct FilterQuickChip: View {
    let label: String
    var icon: String? = nil
    var color: Color = .brandPrimary
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? .white : color)
                }
                Text(label)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white : Color.textSecondary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(isSelected ? color : Color.bgCard)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.springy, value: isSelected)
    }
}

// MARK: - Pending Review Card
private struct PendingReviewCard: View {
    let transaction: TransactionEntity
    let onTap: () -> Void

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₹"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: transaction.amount as NSDecimalNumber) ?? "₹\(transaction.amount)"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    CategoryIconView(slug: transaction.categorySlug, size: 32)
                    Spacer()
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.warningAmber)
                }

                Text({ let n = transaction.merchantName.isEmpty ? transaction.merchantRaw : transaction.merchantName; return n.isEmpty ? "Unknown" : n }())
                    .font(.caption)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                Text(formattedAmount)
                    .font(.amount(13))
                    .foregroundStyle(Color.textPrimary)

                Text("Tap to review")
                    .font(.micro)
                    .foregroundStyle(Color.warningAmber)
            }
            .frame(width: 120)
            .padding(Spacing.md)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(Color.warningAmber.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TransactionFeedView(transactionRepo: TransactionRepositoryImpl(modelContext: try! ModelContainer(for: TransactionModel.self).mainContext))
}
