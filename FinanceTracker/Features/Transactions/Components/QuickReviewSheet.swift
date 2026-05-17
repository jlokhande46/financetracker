import SwiftUI

struct QuickReviewSheet: View {
    /// (transaction, newName, newCategorySlug, newTags, rememberName, rememberCategory, applyToPast)
    var onConfirm: (TransactionEntity, String, String, [String], Bool, Bool, Bool) -> Void
    var onSkip: (TransactionEntity) -> Void
    var onDelete: (TransactionEntity) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container
    @State private var snapshot: [TransactionEntity]
    @State private var index: Int = 0
    @State private var editName: String = ""
    @State private var selectedSlug: String = "others"
    @State private var editTags: [String] = []
    @State private var tagDraft: String = ""
    @State private var rememberName: Bool = true
    @State private var rememberCategory: Bool = true
    @State private var applyToPast: Bool = true
    @FocusState private var nameFieldFocused: Bool
    @FocusState private var tagFieldFocused: Bool

    /// Every tag ever used — feeds autocomplete suggestions.
    private var allKnownTags: [String] {
        guard let container else { return [] }
        var set = Set<String>()
        for t in container.transactionRepo.fetchAll() {
            for tag in t.tags { set.insert(tag) }
        }
        return Array(set).sorted()
    }

    private var tagSuggestions: [String] {
        let draft = tagDraft.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = allKnownTags.filter { !editTags.contains($0) }
        if draft.isEmpty { return Array(pool.prefix(8)) }
        return pool.filter { $0.lowercased().contains(draft) }.prefix(8).map { $0 }
    }

    init(
        transactions: [TransactionEntity],
        onConfirm: @escaping (TransactionEntity, String, String, [String], Bool, Bool, Bool) -> Void,
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
            tagEditor
        }
        .padding(Spacing.base)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - Tag editor

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("TAGS")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)

            if !editTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(editTags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text("#\(tag)")
                                    .font(.micro)
                                    .foregroundStyle(Color.brandPrimary)
                                Button {
                                    editTags.removeAll { $0 == tag }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(Color.brandPrimary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 4)
                            .background(Color.brandPrimary.opacity(0.15))
                            .clipShape(Capsule())
                        }
                    }
                }
            }

            HStack(spacing: Spacing.xs) {
                TextField("Add a tag…", text: $tagDraft)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                    .tint(Color.brandPrimary)
                    .focused($tagFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { commitTagDraft() }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                if !tagDraft.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add", action: commitTagDraft)
                        .font(.caption)
                        .foregroundStyle(Color.brandPrimary)
                }
            }

            if !tagSuggestions.isEmpty && (tagFieldFocused || !tagDraft.isEmpty) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(tagSuggestions, id: \.self) { suggestion in
                            Button {
                                addTag(suggestion)
                            } label: {
                                Text("+ \(suggestion)")
                                    .font(.micro)
                                    .foregroundStyle(Color.textSecondary)
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, 4)
                                    .background(Color.bgElevated)
                                    .overlay(Capsule().stroke(Color.textTertiary.opacity(0.3), lineWidth: 0.5))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func commitTagDraft() {
        let cleaned = tagDraft.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return }
        addTag(cleaned)
    }

    private func addTag(_ tag: String) {
        let cleaned = tag.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, !editTags.contains(cleaned) else { return }
        editTags.append(cleaned)
        tagDraft = ""
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
            if rememberCategory {
                rememberToggleRow(
                    label: "Fix past transactions too",
                    sub: "Re-categorize every past transaction from this merchant",
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
                onConfirm(txn, cleanName, selectedSlug, editTags, rememberName, rememberCategory, applyToPast && rememberCategory)
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
            // Style INSIDE the button's label, otherwise the .background/.frame
            // attaches to a non-tappable wrapper around a tiny "Done" text and
            // only the text fires dismiss.
            Button { dismiss() } label: {
                Text("Done")
                    .font(.titleMedium)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.full))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.base)
        }
        .padding(Spacing.base)
    }

    // MARK: - Helpers

    private func loadCurrent() {
        guard let txn = current else { return }
        editName = txn.merchantName.isEmpty ? txn.merchantRaw : txn.merchantName
        selectedSlug = txn.categorySlug
        editTags = txn.tags
        tagDraft = ""
        // Default everything ON — the user's corrections are remembered AND
        // automatically applied to past transactions for the same merchant.
        rememberName = true
        rememberCategory = true
        applyToPast = true
        nameFieldFocused = false
        tagFieldFocused = false
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
