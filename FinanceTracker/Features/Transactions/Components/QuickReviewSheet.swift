import SwiftUI

struct QuickReviewSheet: View {
    /// (transaction, newName, newCategorySlug, rememberName, rememberCategory, applyToPast)
    var onConfirm: (TransactionEntity, String, String, Bool, Bool, Bool) -> Void
    var onSkip: (TransactionEntity) -> Void
    var onDelete: (TransactionEntity) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: [TransactionEntity]
    @State private var index: Int = 0
    @State private var editName: String = ""
    @State private var selectedSlug: String = "others"
    @State private var rememberName: Bool = true
    @State private var rememberCategory: Bool = true
    @State private var applyToPast: Bool = false
    @FocusState private var nameFieldFocused: Bool

    init(
        transactions: [TransactionEntity],
        onConfirm: @escaping (TransactionEntity, String, String, Bool, Bool, Bool) -> Void,
        onSkip: @escaping (TransactionEntity) -> Void,
        onDelete: @escaping (TransactionEntity) -> Void
    ) {
        // Snapshot the list ONCE so parent mutations during review (e.g. removing a
        // confirmed transaction from the pending list) don't shift our indices.
        self._snapshot = State(initialValue: transactions)
        self.onConfirm = onConfirm
        self.onSkip = onSkip
        self.onDelete = onDelete
    }

    private var current: TransactionEntity? {
        guard index >= 0, index < snapshot.count else { return nil }
        return snapshot[index]
    }

    private var category: CategoryEntity {
        guard let c = current else { return CategoryEntity.find(slug: "others") }
        return CategoryEntity.find(slug: c.categorySlug)
    }

    private var expenseCategories: [CategoryEntity] {
        CategoryEntity.system.filter { !$0.isIncome && !$0.isTransfer }
    }

    private var incomeCategories: [CategoryEntity] {
        CategoryEntity.system.filter { $0.isIncome }
    }

    private var pickerCategories: [CategoryEntity] {
        guard let c = current else { return expenseCategories }
        return c.isCredit ? incomeCategories : expenseCategories
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                if let txn = current {
                    ScrollView {
                        VStack(spacing: Spacing.lg) {
                            progressBar
                            transactionCard(txn)
                                .id(index)   // force fresh view per row — kills state-mix bugs
                                .transition(.opacity)
                            rememberToggles
                                .id(index)
                        }
                        .padding(.horizontal, Spacing.base)
                        .padding(.top, Spacing.sm)
                        .padding(.bottom, 110)
                    }
                    .onAppear { loadCurrent() }

                    // Sticky bottom action bar
                    VStack {
                        Spacer()
                        actionBar(txn)
                            .padding(.horizontal, Spacing.base)
                            .padding(.bottom, Spacing.md)
                    }
                } else {
                    allDoneView
                }
            }
            .navigationTitle("Quick Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgPrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.brandPrimary)
                }
            }
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        HStack(spacing: Spacing.sm) {
            Text("\(min(index + 1, snapshot.count)) of \(snapshot.count)")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
                .monospacedDigit()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.bgElevated)
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.brandPrimary)
                        .frame(width: max(0, geo.size.width * CGFloat(Double(index + 1) / Double(max(1, snapshot.count)))), height: 4)
                        .animation(.easeOut(duration: 0.3), value: index)
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - Transaction card

    @ViewBuilder
    private func transactionCard(_ txn: TransactionEntity) -> some View {
        VStack(spacing: Spacing.lg) {
            // Amount
            Text("\(txn.isCredit ? "+" : "-")₹\(formatAmount(txn.amount))")
                .font(.amount(40, weight: .bold))
                .foregroundStyle(txn.isCredit ? Color.incomeGreen : Color.textPrimary)
                .contentTransition(.numericText())

            // Editable merchant name
            VStack(spacing: 4) {
                TextField("Merchant name", text: $editName)
                    .font(.titleLarge)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .tint(Color.brandPrimary)
                    .focused($nameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { nameFieldFocused = false }
                Text("Tap to rename")
                    .font(.micro)
                    .foregroundStyle(Color.textTertiary)
                    .opacity(nameFieldFocused ? 0 : 1)
            }

            // Detected-as chip + intent badge
            HStack(spacing: Spacing.sm) {
                HStack(spacing: 4) {
                    Image(systemName: category.icon)
                        .font(.system(size: 12))
                    Text("Detected as \(category.name)")
                        .font(.caption)
                }
                .foregroundStyle(category.color)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background(category.color.opacity(0.12))
                .clipShape(Capsule())

                if let intent = category.intent {
                    HStack(spacing: 4) {
                        Image(systemName: intent.icon)
                            .font(.system(size: 10))
                        Text(intent.displayName)
                            .font(.micro)
                    }
                    .foregroundStyle(intent.color)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    .background(intent.color.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            categoryGrid
        }
        .padding(Spacing.base)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("CHANGE CATEGORY")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: Spacing.sm)], spacing: Spacing.sm) {
                ForEach(pickerCategories) { cat in
                    Button {
                        selectedSlug = cat.slug
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(selectedSlug == cat.slug ? .white : cat.color)
                            Text(cat.name)
                                .font(.micro)
                                .foregroundStyle(selectedSlug == cat.slug ? .white : Color.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(selectedSlug == cat.slug ? cat.color : Color.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Remember toggles

    private var rememberToggles: some View {
        VStack(spacing: Spacing.sm) {
            rememberToggleRow(
                label: "Remember this name",
                sub: "Future imports of this merchant will use the renamed version",
                isOn: $rememberName,
                icon: "textformat"
            )
            rememberToggleRow(
                label: "Remember this category",
                sub: "Future transactions from this merchant auto-categorize here",
                isOn: $rememberCategory,
                icon: "tag.fill"
            )
            if rememberCategory && selectedSlug != (current?.categorySlug ?? "") {
                rememberToggleRow(
                    label: "Fix past transactions too",
                    sub: "Update all existing transactions from this merchant",
                    isOn: $applyToPast,
                    icon: "clock.arrow.circlepath"
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.springy, value: rememberCategory)
        .animation(.springy, value: selectedSlug)
    }

    private func rememberToggleRow(label: String, sub: String, isOn: Binding<Bool>, icon: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 28, height: 28)
                .background(Color.brandPrimary.opacity(0.15))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                Text(sub)
                    .font(.micro)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.brandPrimary)
        }
        .padding(Spacing.base)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Sticky action bar

    @ViewBuilder
    private func actionBar(_ txn: TransactionEntity) -> some View {
        HStack(spacing: Spacing.sm) {
            // Prev arrow
            Button {
                guard index > 0 else { return }
                index -= 1
                loadCurrent()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(index > 0 ? Color.textPrimary : Color.textTertiary)
                    .frame(width: 48, height: 48)
                    .background(Color.bgCard)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(index == 0)

            // Delete
            Button {
                onDelete(txn)
                advance()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.expenseRed)
                    .frame(width: 48, height: 48)
                    .background(Color.expenseRed.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // Confirm (big)
            Button {
                let cleanName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
                onConfirm(txn, cleanName, selectedSlug, rememberName, rememberCategory, applyToPast && rememberCategory)
                advance()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Confirm")
                        .font(.titleMedium)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.brandPrimary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.full))
            }
            .buttonStyle(.plain)

            // Skip / Next arrow
            Button {
                onSkip(txn)
                advance()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(Color.bgCard)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - All-done view

    private var allDoneView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.incomeGreen.opacity(0.15))
                    .frame(width: 96, height: 96)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.incomeGreen)
            }
            Text("All caught up!")
                .font(.titleLarge)
                .foregroundStyle(Color.textPrimary)
            Text("No more transactions need review.")
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Button("Done") { dismiss() }
                .font(.titleMedium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.brandPrimary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.full))
                .padding(.horizontal, Spacing.base)
                .buttonStyle(.plain)
        }
        .padding(Spacing.base)
    }

    // MARK: - Helpers

    private func loadCurrent() {
        guard let txn = current else { return }
        editName = txn.merchantName.isEmpty ? txn.merchantRaw : txn.merchantName
        selectedSlug = txn.categorySlug
        // Default to ON — the user wants their corrections to be remembered by default.
        rememberName = true
        rememberCategory = true
        applyToPast = false
        nameFieldFocused = false
    }

    private func advance() {
        nameFieldFocused = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            index += 1
        }
        loadCurrent()
    }

    private func formatAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}
