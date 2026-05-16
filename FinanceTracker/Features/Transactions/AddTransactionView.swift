import SwiftUI

struct AddTransactionView: View {
    var onSave: ((TransactionEntity) -> Void)? = nil

    @State private var amountString: String = ""
    @State private var transactionType: TransactionType = .debit
    @State private var merchantName: String = ""
    @State private var selectedCategorySlug: String = "others"
    @State private var selectedDate: Date = Date()
    @State private var selectedAccountId: UUID? = nil
    @State private var notes: String = ""
    @State private var isDatePickerExpanded: Bool = false
    @FocusState private var isAmountFocused: Bool
    @FocusState private var isMerchantFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container

    private var accounts: [AccountEntity] {
        container?.accountRepo.fetchAll() ?? []
    }

    private var parsedAmount: Decimal {
        Decimal(string: amountString) ?? 0
    }

    private var isValid: Bool {
        parsedAmount > 0
    }

    private var amountFontSize: CGFloat {
        let len = amountString.count
        if len <= 4 { return 52 }
        if len <= 7 { return 44 }
        return 36
    }

    private var incomeCategories: [CategoryEntity] {
        CategoryEntity.system.filter { $0.isIncome }
    }

    private var expenseCategories: [CategoryEntity] {
        CategoryEntity.system.filter { !$0.isIncome && !$0.isTransfer }
    }

    private var displayCategories: [CategoryEntity] {
        transactionType == .credit ? incomeCategories : expenseCategories
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.xl) {

                        // Amount Input
                        amountInputSection

                        // Type Toggle
                        typeToggle

                        // Merchant Name
                        merchantField

                        // Category Picker
                        categoryPicker

                        // Date Picker
                        datePicker

                        // Account Picker
                        if !accounts.isEmpty {
                            accountPicker
                        }

                        // Notes
                        notesField

                        // Save Button
                        saveButton

                        Spacer(minLength: Spacing.xxl)
                    }
                    .padding(.top, Spacing.lg)
                }
            }
            .navigationTitle("Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isAmountFocused = true
                }
            }
            .onChange(of: transactionType) {
                // Reset category to appropriate default when type changes
                if transactionType == .credit {
                    selectedCategorySlug = incomeCategories.first?.slug ?? "salary"
                } else {
                    selectedCategorySlug = "others"
                }
            }
        }
    }

    // MARK: - Subviews

    private var amountInputSection: some View {
        VStack(spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("₹")
                    .font(.amount(amountFontSize * 0.65, weight: .medium))
                    .foregroundStyle(Color.textSecondary)

                Text(amountString.isEmpty ? "0" : amountString)
                    .font(.amount(amountFontSize, weight: .bold))
                    .foregroundStyle(amountString.isEmpty ? Color.textTertiary : (transactionType == .credit ? Color.incomeGreen : Color.textPrimary))
                    .contentTransition(.numericText())
                    .animation(.springy, value: amountString)
            }
            .frame(maxWidth: .infinity)
            .onTapGesture { isAmountFocused = true }

            // Hidden text field for keyboard input
            TextField("", text: $amountString)
                .keyboardType(.decimalPad)
                .focused($isAmountFocused)
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .onChange(of: amountString) { _, newValue in
                    // Validate: only digits and one decimal point
                    let filtered = newValue.filter { $0.isNumber || $0 == "." }
                    let parts = filtered.split(separator: ".", maxSplits: 1)
                    if parts.count == 2 {
                        let decimal = String(parts[1].prefix(2))
                        amountString = "\(parts[0]).\(decimal)"
                    } else {
                        amountString = filtered
                    }
                }

            if !amountString.isEmpty {
                Text(parsedAmount == 0 ? "" : "₹ \(amountString)")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, Spacing.xxl)
        .padding(.horizontal, Spacing.base)
        .frame(maxWidth: .infinity)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .padding(.horizontal, Spacing.base)
    }

    private var typeToggle: some View {
        HStack(spacing: 0) {
            ForEach([TransactionType.debit, TransactionType.credit], id: \.self) { type in
                Button {
                    withAnimation(.springy) { transactionType = type }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: type == .debit ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                        Text(type == .debit ? "Expense" : "Income")
                            .font(.titleMedium)
                    }
                    .foregroundStyle(transactionType == type ? .white : Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        transactionType == type
                            ? (type == .debit ? Color.expenseRed : Color.incomeGreen)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .padding(.horizontal, Spacing.base)
    }

    private var merchantField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Merchant / Payee")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, Spacing.base)

            TextField("e.g. Swiggy, Zomato, Amazon...", text: $merchantName)
                .font(.bodyMedium)
                .foregroundStyle(Color.textPrimary)
                .tint(Color.brandPrimary)
                .focused($isMerchantFocused)
                .submitLabel(.done)
                .onSubmit { isMerchantFocused = false }
                .padding(Spacing.base)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                .padding(.horizontal, Spacing.base)
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Category")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, Spacing.base)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(displayCategories) { cat in
                        CategoryChip(
                            category: cat,
                            isSelected: selectedCategorySlug == cat.slug
                        ) {
                            isAmountFocused = false
                            isMerchantFocused = false
                            withAnimation(.springy) {
                                selectedCategorySlug = cat.slug
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.base)
            }
        }
    }

    private var datePicker: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Date")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, Spacing.base)

            Button {
                withAnimation(.springy) { isDatePickerExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.brandPrimary)

                    Text(formattedSelectedDate)
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textPrimary)

                    Spacer()

                    Image(systemName: isDatePickerExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(Spacing.base)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.base)

            if isDatePickerExpanded {
                DatePicker("", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .tint(Color.brandPrimary)
                    .colorScheme(.dark)
                    .padding(.horizontal, Spacing.base)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var accountPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Account")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, Spacing.base)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    // None option
                    Button {
                        withAnimation(.springy) { selectedAccountId = nil }
                    } label: {
                        Text("None")
                            .font(.bodyMedium)
                            .foregroundStyle(selectedAccountId == nil ? .white : Color.textSecondary)
                            .padding(.horizontal, Spacing.base)
                            .padding(.vertical, Spacing.sm)
                            .background(selectedAccountId == nil ? Color.brandPrimary : Color.bgCard)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    ForEach(accounts) { account in
                        Button {
                            withAnimation(.springy) { selectedAccountId = account.id }
                        } label: {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: account.type.icon)
                                    .font(.system(size: 13))
                                Text(account.name)
                                    .font(.bodyMedium)
                            }
                            .foregroundStyle(selectedAccountId == account.id ? .white : Color.textSecondary)
                            .padding(.horizontal, Spacing.base)
                            .padding(.vertical, Spacing.sm)
                            .background(selectedAccountId == account.id ? Color(hex: account.colorHex) : Color.bgCard)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .animation(.springy, value: selectedAccountId)
                    }
                }
                .padding(.horizontal, Spacing.base)
            }
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Notes (optional)")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, Spacing.base)

            TextField("Add a note...", text: $notes, axis: .vertical)
                .font(.bodyMedium)
                .foregroundStyle(Color.textPrimary)
                .tint(Color.brandPrimary)
                .lineLimit(3...5)
                .padding(Spacing.base)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                .padding(.horizontal, Spacing.base)
        }
    }

    private var saveButton: some View {
        Button {
            saveTransaction()
        } label: {
            Text("Add Transaction")
                .font(.titleMedium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.base)
                .background(isValid ? Color.brandPrimary : Color.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: Radius.full))
                .animation(.springy, value: isValid)
        }
        .buttonStyle(.plain)
        .disabled(!isValid)
        .padding(.horizontal, Spacing.base)
    }

    // MARK: - Helpers

    private var formattedSelectedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDate) { return "Today" }
        if calendar.isDateInYesterday(selectedDate) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, d MMM yyyy"
        return f.string(from: selectedDate)
    }

    private func saveTransaction() {
        guard isValid else { return }

        let txn = TransactionEntity(
            amount: parsedAmount,
            type: transactionType,
            merchantRaw: merchantName,
            merchantName: merchantName,
            categorySlug: selectedCategorySlug,
            date: selectedDate,
            source: .manual,
            confidence: 1.0,
            isConfirmed: true,
            isRecurring: false,
            notes: notes.isEmpty ? nil : notes,
            accountId: selectedAccountId
        )

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        onSave?(txn)
        dismiss()
    }
}

// MARK: - Category Chip
private struct CategoryChip: View {
    let category: CategoryEntity
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .white : category.color)

                Text(category.name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white : Color.textSecondary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(isSelected ? category.color : Color.bgCard)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.springy, value: isSelected)
    }
}

#Preview {
    AddTransactionView()
}
