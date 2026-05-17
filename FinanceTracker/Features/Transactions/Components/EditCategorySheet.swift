import SwiftUI

struct EditCategorySheet: View {
    let transaction: TransactionEntity
    /// (newSlug, rememberForMerchant, applyToPast)
    var onSave: (String, Bool, Bool) -> Void

    @State private var selectedSlug: String
    @State private var rememberForMerchant: Bool = false
    @State private var applyToPast: Bool = false
    @State private var searchText: String = ""
    @Environment(\.dismiss) private var dismiss

    private var merchantName: String {
        transaction.merchantName.isEmpty ? transaction.merchantRaw : transaction.merchantName
    }

    private var filteredCategories: [CategoryEntity] {
        let all = CategoryEntity.system
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₹"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: transaction.amount as NSDecimalNumber) ?? "₹\(transaction.amount)"
    }

    init(transaction: TransactionEntity, onSave: @escaping (String, Bool) -> Void) {
        self.transaction = transaction
        self.onSave = onSave
        self._selectedSlug = State(initialValue: transaction.categorySlug)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.xl) {

                        // Transaction context card
                        HStack(spacing: Spacing.md) {
                            CategoryIconView(slug: selectedSlug, size: 44)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(merchantName)
                                    .font(.titleMedium)
                                    .foregroundStyle(Color.textPrimary)
                                Text(formattedAmount)
                                    .font(.amount(15))
                                    .foregroundStyle(transaction.isCredit ? Color.incomeGreen : Color.textSecondary)
                            }

                            Spacer()
                        }
                        .padding(Spacing.base)
                        .background(Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                        .padding(.horizontal, Spacing.base)

                        // Search
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.textTertiary)

                            TextField("Search categories...", text: $searchText)
                                .font(.bodyMedium)
                                .foregroundStyle(Color.textPrimary)
                                .tint(Color.brandPrimary)
                        }
                        .padding(Spacing.md)
                        .background(Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        .padding(.horizontal, Spacing.base)

                        // Category grid
                        LazyVGrid(columns: columns, spacing: Spacing.md) {
                            ForEach(filteredCategories) { cat in
                                CategoryGridButton(
                                    category: cat,
                                    isSelected: selectedSlug == cat.slug
                                ) {
                                    withAnimation(.springy) {
                                        selectedSlug = cat.slug
                                    }
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.impactOccurred()
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.base)

                        // Remember toggle
                        VStack(spacing: Spacing.sm) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Remember for \(merchantName)")
                                        .font(.bodyMedium)
                                        .foregroundStyle(Color.textPrimary)
                                    Text("Auto-categorize future transactions")
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                }
                                Spacer()
                                Toggle("", isOn: $rememberForMerchant)
                                    .tint(Color.brandPrimary)
                                    .labelsHidden()
                            }
                            .padding(Spacing.base)
                            .background(Color.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

                            // Show "apply to past" only when remembering and category changed
                            if rememberForMerchant && selectedSlug != transaction.categorySlug {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Fix past transactions too")
                                            .font(.bodyMedium)
                                            .foregroundStyle(Color.textPrimary)
                                        Text("Update all existing transactions from this merchant")
                                            .font(.caption)
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $applyToPast)
                                        .tint(Color.brandPrimary)
                                        .labelsHidden()
                                }
                                .padding(Spacing.base)
                                .background(Color.bgCard)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .animation(.springy, value: rememberForMerchant)
                        .padding(.horizontal, Spacing.base)

                        // Save button
                        Button {
                            onSave(selectedSlug, rememberForMerchant, applyToPast && rememberForMerchant)
                            dismiss()
                        } label: {
                            Text("Save Category")
                                .font(.titleMedium)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.base)
                                .background(Color.brandPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.full))
                        }
                        .padding(.horizontal, Spacing.base)
                        .padding(.bottom, Spacing.xxl)
                    }
                    .padding(.top, Spacing.base)
                }
            }
            .navigationTitle("Change Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }
}

// MARK: - Category Grid Button
private struct CategoryGridButton: View {
    let category: CategoryEntity
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(category.color.opacity(isSelected ? 0.3 : 0.12))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    isSelected ? Color.brandPrimary : Color.clear,
                                    lineWidth: 2
                                )
                        )

                    Image(systemName: category.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(category.color)
                }

                Text(category.name)
                    .font(.micro)
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(isSelected ? Color.brandPrimary.opacity(0.08) : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .animation(.springy, value: isSelected)
    }
}

#Preview {
    EditCategorySheet(
        transaction: TransactionEntity(
            amount: 450,
            type: .debit,
            merchantName: "Swiggy",
            categorySlug: "food"
        ),
        onSave: { _, _ in }
    )
}
