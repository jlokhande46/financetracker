import SwiftUI

struct CategoryReviewSheet: View {
    let transaction: TransactionEntity
    var onConfirm: (String, Bool) -> Void
    var onSkip: () -> Void

    @State private var selectedSlug: String? = nil
    @State private var rememberForMerchant: Bool = false
    @Environment(\.dismiss) private var dismiss

    private var merchantName: String {
        transaction.merchantName.isEmpty ? transaction.merchantRaw : transaction.merchantName
    }

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₹"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: transaction.amount as NSDecimalNumber) ?? "₹\(transaction.amount)"
    }

    // Top candidate categories — current first, then common expense categories
    private var candidateCategories: [CategoryEntity] {
        let current = CategoryEntity.find(slug: transaction.categorySlug)
        var others = CategoryEntity.system.filter { $0.slug != transaction.categorySlug && !$0.isIncome }
        others = Array(others.prefix(5))
        return [current] + others
    }

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {

                // Drag indicator
                Capsule()
                    .fill(Color.textTertiary.opacity(0.5))
                    .frame(width: 36, height: 4)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.lg)

                ScrollView {
                    VStack(spacing: Spacing.xl) {

                        // Transaction mini card
                        VStack(spacing: Spacing.md) {
                            HStack(spacing: Spacing.md) {
                                ZStack {
                                    Circle()
                                        .fill(Color.warningAmber.opacity(0.15))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: "questionmark")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(Color.warningAmber)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(merchantName)
                                        .font(.titleMedium)
                                        .foregroundStyle(Color.textPrimary)
                                    Text("Low confidence — needs review")
                                        .font(.caption)
                                        .foregroundStyle(Color.warningAmber)
                                }

                                Spacer()

                                Text(formattedAmount)
                                    .font(.amount(17))
                                    .foregroundStyle(Color.textPrimary)
                            }
                        }
                        .padding(Spacing.base)
                        .background(Color.warningAmber.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.lg)
                                .strokeBorder(Color.warningAmber.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal, Spacing.base)

                        // Heading
                        VStack(spacing: Spacing.xs) {
                            Text("What is this transaction?")
                                .font(.titleLarge)
                                .foregroundStyle(Color.textPrimary)
                            Text("Help us categorize it correctly")
                                .font(.bodyMedium)
                                .foregroundStyle(Color.textSecondary)
                        }

                        // Category 2x3 grid
                        LazyVGrid(columns: columns, spacing: Spacing.md) {
                            ForEach(candidateCategories) { cat in
                                ReviewCategoryButton(
                                    category: cat,
                                    isSelected: selectedSlug == cat.slug,
                                    isCurrentGuess: cat.slug == transaction.categorySlug
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
                        if selectedSlug != nil {
                            HStack {
                                Image(systemName: rememberForMerchant ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 20))
                                    .foregroundStyle(rememberForMerchant ? Color.brandPrimary : Color.textTertiary)

                                Text("Remember for \(merchantName) always")
                                    .font(.bodyMedium)
                                    .foregroundStyle(Color.textPrimary)

                                Spacer()
                            }
                            .padding(.horizontal, Spacing.base)
                            .onTapGesture {
                                withAnimation(.springy) {
                                    rememberForMerchant.toggle()
                                }
                            }

                            // Confirm button
                            Button {
                                if let slug = selectedSlug {
                                    onConfirm(slug, rememberForMerchant)
                                    dismiss()
                                }
                            } label: {
                                Text("Confirm Category")
                                    .font(.titleMedium)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Spacing.base)
                                    .background(Color.brandPrimary)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.full))
                            }
                            .padding(.horizontal, Spacing.base)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Skip button
                        Button {
                            onSkip()
                            dismiss()
                        } label: {
                            Text("Skip for now")
                                .font(.bodyMedium)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(.bottom, Spacing.xxl)
                    }
                    .padding(.bottom, Spacing.xxl)
                }
            }
        }
    }
}

// MARK: - Review Category Button
private struct ReviewCategoryButton: View {
    let category: CategoryEntity
    let isSelected: Bool
    let isCurrentGuess: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(category.color.opacity(isSelected ? 0.3 : 0.15))
                            .frame(width: 56, height: 56)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        isSelected ? Color.brandPrimary : Color.clear,
                                        lineWidth: 2.5
                                    )
                            )

                        Image(systemName: category.icon)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(category.color)
                    }

                    if isCurrentGuess && !isSelected {
                        Circle()
                            .fill(Color.warningAmber)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.black)
                            )
                            .offset(x: 2, y: -2)
                    }

                    if isSelected {
                        Circle()
                            .fill(Color.brandPrimary)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                            .offset(x: 4, y: -4)
                    }
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
    CategoryReviewSheet(
        transaction: TransactionEntity(
            amount: 840,
            type: .debit,
            merchantRaw: "SWIGGY",
            merchantName: "Swiggy",
            categorySlug: "food",
            source: .sms,
            confidence: 0.65,
            isConfirmed: false
        ),
        onConfirm: { _, _ in },
        onSkip: {}
    )
}
