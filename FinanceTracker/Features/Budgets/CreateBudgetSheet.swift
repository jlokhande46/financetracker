import SwiftUI

struct CreateBudgetSheet: View {

    @Bindable var viewModel: BudgetsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategorySlug: String? = nil
    @State private var amountString: String = ""
    @State private var selectedPeriod: BudgetPeriod = .monthly
    @State private var showValidationError = false
    @State private var validationMessage = ""
    @State private var successPulse = false

    private var availableCategories: [CategoryEntity] {
        let existingSlugs = Set(viewModel.budgets.map(\.categorySlug))
        return CategoryEntity.system.filter { !$0.isIncome && !$0.isTransfer && !existingSlugs.contains($0.slug) }
    }

    private var parsedAmount: Decimal? {
        let cleaned = amountString.replacingOccurrences(of: ",", with: "")
        return Decimal(string: cleaned)
    }

    private var isValid: Bool {
        selectedCategorySlug != nil && (parsedAmount ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        // Amount input
                        amountSection

                        // Period picker
                        periodSection

                        // Category picker
                        categorySection

                        // Validation error
                        if showValidationError {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.expenseRed)
                                Text(validationMessage)
                                    .font(.caption)
                                    .foregroundColor(.expenseRed)
                            }
                            .padding(Spacing.md)
                            .background(Color.expenseRed.opacity(0.1))
                            .cornerRadius(Radius.md)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }

                        // Create button
                        createButton

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, Spacing.base)
                    .padding(.top, Spacing.sm)
                }
            }
            .navigationTitle("New Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bgPrimary)
    }

    // MARK: - Amount Section
    private var amountSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("BUDGET AMOUNT")
                .font(.micro)
                .fontWeight(.semibold)
                .foregroundColor(.textSecondary)
                .kerning(1.2)

            HStack(alignment: .center, spacing: Spacing.sm) {
                Text("₹")
                    .font(Font.amount(36))
                    .fontWeight(.bold)
                    .foregroundColor(.brandPrimary)

                TextField("0", text: $amountString)
                    .font(Font.amount(36))
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                    .keyboardType(.numberPad)
                    .onChange(of: amountString) { _, new in
                        // Format with commas
                        let digits = new.filter(\.isNumber)
                        if let value = Int(digits) {
                            let formatter = NumberFormatter()
                            formatter.numberStyle = .decimal
                            formatter.groupingSeparator = ","
                            amountString = formatter.string(from: NSNumber(value: value)) ?? digits
                        } else {
                            amountString = digits
                        }
                        showValidationError = false
                    }
                    .tint(.brandPrimary)

                if !amountString.isEmpty {
                    Button(action: { amountString = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.textSecondary.opacity(0.6))
                    }
                }
            }
            .padding(Spacing.base)
            .background(Color.bgCard)
            .cornerRadius(Radius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(
                        amountString.isEmpty ? Color.divider : Color.brandPrimary.opacity(0.4),
                        lineWidth: 1
                    )
            )

            // Quick amount suggestions
            HStack(spacing: Spacing.sm) {
                ForEach([1000, 3000, 5000, 10000, 15000], id: \.self) { amount in
                    Button(action: {
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        amountString = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
                    }) {
                        Text("₹\(amount / 1000)K")
                            .font(.micro)
                            .fontWeight(.semibold)
                            .foregroundColor(parsedAmount == Decimal(amount) ? .brandPrimary : .textSecondary)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 6)
                            .background(
                                parsedAmount == Decimal(amount)
                                    ? Color.brandPrimary.opacity(0.15)
                                    : Color.bgCard
                            )
                            .cornerRadius(Radius.sm)
                    }
                }
            }
        }
    }

    // MARK: - Period Section
    private var periodSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("BUDGET PERIOD")
                .font(.micro)
                .fontWeight(.semibold)
                .foregroundColor(.textSecondary)
                .kerning(1.2)

            HStack(spacing: 0) {
                ForEach(BudgetPeriod.allCases, id: \.self) { period in
                    Button(action: {
                        withAnimation(.springy) {
                            selectedPeriod = period
                        }
                    }) {
                        Text(period.displayName)
                            .font(.bodyMedium)
                            .fontWeight(selectedPeriod == period ? .semibold : .regular)
                            .foregroundColor(selectedPeriod == period ? .white : .textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(
                                selectedPeriod == period
                                    ? Color.brandPrimary
                                    : Color.clear
                            )
                    }
                }
            }
            .background(Color.bgCard)
            .cornerRadius(Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    // MARK: - Category Section
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("CATEGORY")
                    .font(.micro)
                    .fontWeight(.semibold)
                    .foregroundColor(.textSecondary)
                    .kerning(1.2)

                if availableCategories.count < CategoryEntity.system.count {
                    Spacer()
                    Text("Already budgeted categories hidden")
                        .font(.micro)
                        .foregroundColor(.textSecondary.opacity(0.6))
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 4),
                spacing: Spacing.sm
            ) {
                ForEach(availableCategories) { cat in
                    categoryChip(cat)
                }
            }

            if availableCategories.isEmpty {
                Text("All categories have budgets set.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity)
                    .background(Color.bgCard)
                    .cornerRadius(Radius.md)
            }
        }
    }

    private func categoryChip(_ cat: CategoryEntity) -> some View {
        let isSelected = selectedCategorySlug == cat.slug

        return Button(action: {
            withAnimation(.springy) {
                selectedCategorySlug = isSelected ? nil : cat.slug
                showValidationError = false
            }
        }) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? cat.color.opacity(0.3) : cat.color.opacity(0.12))
                        .frame(width: 52, height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(isSelected ? cat.color : Color.clear, lineWidth: 1.5)
                        )

                    Image(systemName: cat.icon)
                        .font(.system(size: 22))

                    if isSelected {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(cat.color)
                                    .background(Color.bgPrimary.clipShape(Circle()))
                            }
                            Spacer()
                        }
                        .padding(3)
                    }
                }

                Text(cat.name)
                    .font(.micro)
                    .foregroundColor(isSelected ? cat.color : .textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.springy, value: isSelected)
    }

    // MARK: - Create Button
    private var createButton: some View {
        Button(action: createBudget) {
            HStack(spacing: Spacing.sm) {
                if successPulse {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                    Text("Create Budget")
                        .font(.titleMedium)
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                isValid
                    ? Color.brandPrimary
                    : Color.brandPrimary.opacity(0.4)
            )
            .cornerRadius(Radius.xl)
            .shadow(color: isValid ? Color.brandPrimary.opacity(0.35) : .clear, radius: 12, x: 0, y: 6)
            .scaleEffect(successPulse ? 0.97 : 1.0)
        }
        .disabled(!isValid)
        .animation(.springy, value: isValid)
        .animation(.springy, value: successPulse)
    }

    // MARK: - Actions
    private func createBudget() {
        guard let slug = selectedCategorySlug else {
            showError("Please select a category.")
            return
        }
        guard let amount = parsedAmount, amount > 0 else {
            showError("Please enter a valid budget amount.")
            return
        }

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()

        withAnimation(.springy) { successPulse = true }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            generator.notificationOccurred(.success)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            viewModel.createBudget(categorySlug: slug, amount: amount, period: selectedPeriod)
            dismiss()
        }
    }

    private func showError(_ message: String) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)

        withAnimation(.springy) {
            validationMessage = message
            showValidationError = true
        }
    }
}

