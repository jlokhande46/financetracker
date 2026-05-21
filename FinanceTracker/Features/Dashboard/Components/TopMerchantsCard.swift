import SwiftUI

struct TopMerchantsCard: View {

    let merchants: [MerchantSpend]
    var onViewAll: (() -> Void)? = nil
    @AppStorage("hideAmounts") private var hideAmounts: Bool = false

    private var maxAmount: Decimal {
        merchants.map(\.amount).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TOP MERCHANTS")
                        .font(.micro)
                        .fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                        .kerning(1.2)
                    Text("Where you spend most")
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)
                }
                Spacer()
                Button(action: { onViewAll?() }) {
                    Text("View all")
                        .font(.caption)
                        .foregroundColor(.brandPrimary)
                }
            }

            if merchants.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(merchants.enumerated()), id: \.element.id) { idx, merchant in
                        merchantRow(merchant: merchant, rank: idx + 1)

                        if idx < merchants.count - 1 {
                            Divider()
                                .background(Color.chartGrid)
                                .padding(.vertical, Spacing.xs)
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    private func merchantRow(merchant: MerchantSpend, rank: Int) -> some View {
        let cat = CategoryEntity.find(slug: merchant.categorySlug)
        let progress = maxAmount > 0
            ? Double(truncating: (merchant.amount / maxAmount) as NSDecimalNumber)
            : 0

        return HStack(spacing: Spacing.md) {
            // Merchant initial circle
            ZStack {
                Circle()
                    .fill(cat.color.opacity(0.2))
                    .frame(width: 40, height: 40)

                Text(String(merchant.merchantName.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(cat.color)
            }

            // Name + progress
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(merchant.merchantName)
                        .font(.bodyMedium)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text(merchant.amount.currencyString(hidden: hideAmounts))
                        .font(Font.amount(14))
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                }

                HStack(spacing: Spacing.sm) {
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(cat.color.opacity(0.75))
                                .frame(width: geo.size.width * progress, height: 4)
                        }
                    }
                    .frame(height: 4)

                    Text("\(merchant.count) order\(merchant.count == 1 ? "" : "s")")
                        .font(.micro)
                        .foregroundColor(.textSecondary)
                        .frame(minWidth: 50, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: Spacing.sm) {
                Image(systemName: "bag")
                    .font(.system(size: 28))
                    .foregroundColor(.textSecondary.opacity(0.4))
                Text("No merchant data")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            .padding(.vertical, Spacing.lg)
            Spacer()
        }
    }
}

#Preview {
    TopMerchantsCard(merchants: [
        MerchantSpend(merchantName: "Swiggy", amount: 6400, count: 12, categorySlug: "food"),
        MerchantSpend(merchantName: "Amazon", amount: 4200, count: 5, categorySlug: "shopping"),
        MerchantSpend(merchantName: "Uber", amount: 3100, count: 18, categorySlug: "transport"),
        MerchantSpend(merchantName: "Netflix", amount: 799, count: 1, categorySlug: "entertainment"),
        MerchantSpend(merchantName: "BigBasket", amount: 2800, count: 3, categorySlug: "groceries"),
    ])
    .padding()
    .background(Color.bgPrimary)
}
