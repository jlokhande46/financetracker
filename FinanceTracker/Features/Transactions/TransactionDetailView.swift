import SwiftUI

struct TransactionDetailView: View {
    let transaction: TransactionEntity
    var onUpdate: ((TransactionEntity) -> Void)? = nil
    var onDelete: ((UUID) -> Void)? = nil

    @State private var editableTransaction: TransactionEntity
    @State private var showEditCategory: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showRawContent: Bool = false
    @State private var newTag: String = ""
    @State private var showAddTag: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container

    private var category: CategoryEntity {
        CategoryEntity.find(slug: editableTransaction.categorySlug)
    }

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₹"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter.string(from: editableTransaction.amount as NSDecimalNumber) ?? "₹\(editableTransaction.amount)"
    }

    private var amountColor: Color {
        editableTransaction.isCredit ? .incomeGreen : .textPrimary
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM yyyy"
        return f.string(from: editableTransaction.date)
    }

    private var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: editableTransaction.date)
    }

    private var accountName: String {
        guard let accountId = editableTransaction.accountId else { return "Not linked" }
        let accounts = container?.accountRepo.fetchAll() ?? []
        return accounts.first { $0.id == accountId }?.name ?? "Unknown Account"
    }

    private var availableAccounts: [AccountEntity] {
        container?.accountRepo.fetchAll() ?? []
    }

    init(transaction: TransactionEntity, onUpdate: ((TransactionEntity) -> Void)? = nil, onDelete: ((UUID) -> Void)? = nil) {
        self.transaction = transaction
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self._editableTransaction = State(initialValue: transaction)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.xl) {

                        // Pending Review Banner
                        if editableTransaction.needsReview {
                            pendingReviewBanner
                        }

                        // Amount Header
                        amountHeader

                        // Category Badge
                        categoryBadge
                            .padding(.top, -Spacing.md)

                        // Info Grid
                        infoGrid

                        // Account picker
                        accountPicker

                        // Notes Section
                        notesSection

                        // Tags Section
                        tagsSection

                        // Recurring Toggle
                        recurringToggle

                        // Raw Content
                        if let raw = editableTransaction.rawContent, !raw.isEmpty {
                            rawContentSection(raw: raw)
                        }

                        // Edit Category Button
                        editCategoryButton

                        // Delete Button
                        deleteButton

                        Spacer(minLength: Spacing.xxl)
                    }
                    .padding(.vertical, Spacing.lg)
                }
            }
            .navigationTitle(editableTransaction.merchantName.isEmpty ? editableTransaction.merchantRaw : editableTransaction.merchantName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.brandPrimary)
                }
            }
            .sheet(isPresented: $showEditCategory) {
                EditCategorySheet(transaction: editableTransaction) { newSlug, remember, applyToPast in
                    editableTransaction.categorySlug = newSlug
                    editableTransaction.isConfirmed = true
                    onUpdate?(editableTransaction)
                    if remember {
                        let merchantKey = editableTransaction.merchantName.isEmpty
                            ? editableTransaction.merchantRaw
                            : editableTransaction.merchantName
                        MerchantRuleStore.shared.saveRule(merchant: merchantKey, categorySlug: newSlug)
                    }
                    if applyToPast {
                        container?.transactionRepo.bulkRecategorize(
                            merchantRaw: editableTransaction.merchantRaw,
                            merchantNameKey: editableTransaction.merchantName,
                            newSlug: newSlug
                        )
                    }
                }
            }
            .alert("Delete Transaction", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    onDelete?(editableTransaction.id)
                    dismiss()
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    // MARK: - Subviews

    private var pendingReviewBanner: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.warningAmber)

            VStack(alignment: .leading, spacing: 2) {
                Text("Needs Review")
                    .font(.titleMedium)
                    .foregroundStyle(Color.warningAmber)
                Text("Category was auto-detected with low confidence")
                    .font(.caption)
                    .foregroundStyle(Color.warningAmber.opacity(0.7))
            }

            Spacer()

            Button {
                showEditCategory = true
            } label: {
                Text("Fix")
                    .font(.caption)
                    .foregroundStyle(Color.warningAmber)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.warningAmber.opacity(0.2))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.base)
        .background(Color.warningAmber.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Color.warningAmber.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, Spacing.base)
    }

    private var amountHeader: some View {
        VStack(spacing: Spacing.sm) {
            Text("\(editableTransaction.isCredit ? "+" : "-")\(formattedAmount)")
                .font(.amount(44, weight: .bold))
                .foregroundStyle(amountColor)
                .contentTransition(.numericText())

            TextField("Merchant name", text: Binding(
                get: { editableTransaction.merchantName.isEmpty ? editableTransaction.merchantRaw : editableTransaction.merchantName },
                set: { editableTransaction.merchantName = $0 }
            ))
            .font(.titleLarge)
            .foregroundStyle(Color.textSecondary)
            .tint(Color.brandPrimary)
            .multilineTextAlignment(.center)
            .submitLabel(.done)
            .onSubmit { onUpdate?(editableTransaction) }
            .padding(.horizontal, Spacing.base)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.base)
    }

    private var categoryBadge: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: category.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(category.color)

            Text(category.name)
                .font(.bodyMedium)
                .foregroundStyle(category.color)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.sm)
        .background(category.color.opacity(0.15))
        .clipShape(Capsule())
    }

    private var infoGrid: some View {
        VStack(spacing: 1) {
            InfoRow(label: "Date", value: formattedDate)
            InfoRow(label: "Time", value: formattedTime)
            InfoRow(label: "Source", value: editableTransaction.source.displayName)
            InfoRow(label: "Account", value: accountName)
            if let upi = editableTransaction.upiRef, !upi.isEmpty {
                InfoRow(label: "UPI Ref", value: upi)
            }
            if let bank = editableTransaction.bankRef, !bank.isEmpty {
                InfoRow(label: "Bank Ref", value: bank)
            }
            InfoRow(label: "Confidence", value: String(format: "%.0f%%", editableTransaction.confidence * 100))
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .padding(.horizontal, Spacing.base)
    }

    private var accountPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("ACCOUNT / CARD")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, Spacing.base)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    Button {
                        editableTransaction.accountId = nil
                        onUpdate?(editableTransaction)
                    } label: {
                        Text("None")
                            .font(.caption)
                            .foregroundStyle(editableTransaction.accountId == nil ? Color.white : Color.textSecondary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(editableTransaction.accountId == nil ? Color.brandPrimary : Color.bgCard)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    ForEach(availableAccounts) { account in
                        Button {
                            editableTransaction.accountId = account.id
                            onUpdate?(editableTransaction)
                        } label: {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: account.type.icon)
                                    .font(.system(size: 11))
                                Text(account.name)
                                    .font(.caption)
                                if let last4 = account.last4 {
                                    Text("••\(last4)")
                                        .font(.micro)
                                        .opacity(0.7)
                                }
                            }
                            .foregroundStyle(editableTransaction.accountId == account.id ? Color.white : Color.textSecondary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(editableTransaction.accountId == account.id ? Color(hex: account.colorHex) : Color.bgCard)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.base)
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Notes")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, Spacing.base)

            TextField("Add a note...", text: Binding(
                get: { editableTransaction.notes ?? "" },
                set: { editableTransaction.notes = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .font(.bodyMedium)
            .foregroundStyle(Color.textPrimary)
            .tint(Color.brandPrimary)
            .lineLimit(3...6)
            .padding(Spacing.base)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .padding(.horizontal, Spacing.base)
            .onChange(of: editableTransaction.notes) {
                onUpdate?(editableTransaction)
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Tags")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .textCase(.uppercase)
                Spacer()
                Button {
                    withAnimation(.springy) { showAddTag.toggle() }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.brandPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.base)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(editableTransaction.tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.caption)
                                .foregroundStyle(Color.textPrimary)

                            Button {
                                withAnimation(.springy) {
                                    editableTransaction.tags.removeAll { $0 == tag }
                                    onUpdate?(editableTransaction)
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.bgElevated)
                        .clipShape(Capsule())
                    }

                    if editableTransaction.tags.isEmpty {
                        Text("No tags yet")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .padding(.horizontal, Spacing.base)
            }

            if showAddTag {
                HStack(spacing: Spacing.sm) {
                    TextField("New tag...", text: $newTag)
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                        .tint(Color.brandPrimary)
                        .onSubmit { addTag() }

                    Button(action: addTag) {
                        Text("Add")
                            .font(.caption)
                            .foregroundStyle(Color.brandPrimary)
                    }
                    .buttonStyle(.plain)
                    .disabled(newTag.isEmpty)
                }
                .padding(Spacing.md)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .padding(.horizontal, Spacing.base)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var recurringToggle: some View {
        HStack {
            Image(systemName: "repeat")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(editableTransaction.isRecurring ? Color.brandPrimary : Color.textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Recurring Transaction")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                Text("Mark if this repeats regularly")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            Toggle("", isOn: $editableTransaction.isRecurring)
                .tint(Color.brandPrimary)
                .labelsHidden()
                .onChange(of: editableTransaction.isRecurring) {
                    onUpdate?(editableTransaction)
                }
        }
        .padding(Spacing.base)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .padding(.horizontal, Spacing.base)
    }

    private func rawContentSection(raw: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Button {
                withAnimation(.springy) { showRawContent.toggle() }
            } label: {
                HStack {
                    Image(systemName: showRawContent ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textSecondary)

                    Text("Show original message")
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textSecondary)

                    Spacer()
                }
                .padding(.horizontal, Spacing.base)
            }
            .buttonStyle(.plain)

            if showRawContent {
                Text(raw)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
                    .padding(Spacing.base)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .padding(.horizontal, Spacing.base)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var editCategoryButton: some View {
        Button {
            showEditCategory = true
        } label: {
            HStack {
                CategoryIconView(slug: editableTransaction.categorySlug, size: 32)

                Text("Change Category")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(Spacing.base)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.base)
    }

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            Label("Delete Transaction", systemImage: "trash")
                .font(.bodyMedium)
                .foregroundStyle(Color.expenseRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.base)
                .background(Color.expenseRed.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.base)
    }

    // MARK: - Helpers
    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !editableTransaction.tags.contains(tag) else { return }
        withAnimation(.springy) {
            editableTransaction.tags.append(tag)
            newTag = ""
            showAddTag = false
            onUpdate?(editableTransaction)
        }
    }
}

// MARK: - Info Row
private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.bodyMedium)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.md)
        .background(Color.bgCard)
    }
}

#Preview {
    TransactionDetailView(
        transaction: TransactionEntity(
            amount: 840,
            type: .debit,
            merchantRaw: "SWIGGY",
            merchantName: "Swiggy",
            categorySlug: "food",
            source: .upi,
            confidence: 0.72,
            isConfirmed: false,
            isRecurring: false,
            tags: ["lunch", "work"],
            notes: "Team lunch",
            upiRef: "UPI/123456789",
            bankRef: "HDFC/7890",
            rawContent: "INR 840.00 debited from HDFC A/c XXXX1234 on 15-05-26. UPI:SWIGGY. Avl Bal Rs.45,230.00"
        )
    )
}
