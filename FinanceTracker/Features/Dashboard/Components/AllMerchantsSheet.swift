import SwiftUI

struct AllMerchantsSheet: View {
    let merchants: [MerchantSpend]

    @Environment(\.dismiss) private var dismiss

    private var maxAmount: Decimal {
        merchants.first?.amount ?? 1
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(merchants.enumerated()), id: \.element.id) { idx, m in
                            row(merchant: m, rank: idx + 1)
                            if idx < merchants.count - 1 {
                                Divider()
                                    .background(Color.textTertiary.opacity(0.15))
                                    .padding(.leading, 64)
                            }
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                    .background(Color.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                    .padding(.horizontal, Spacing.base)
                    .padding(.top, Spacing.md)
                }
            }
            .navigationTitle("Top Merchants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgPrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.brandPrimary)
                }
            }
        }
    }

    private func row(merchant: MerchantSpend, rank: Int) -> some View {
        let cat = CategoryEntity.find(slug: merchant.categorySlug)
        let pct = maxAmount > 0
            ? Double(truncating: (merchant.amount / maxAmount) as NSDecimalNumber)
            : 0
        return HStack(spacing: Spacing.md) {
            Text("\(rank)")
                .font(.amount(13))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 24)
            CategoryIconView(slug: merchant.categorySlug, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(merchant.merchantName)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(cat.name)
                        .font(.micro)
                        .foregroundStyle(Color.textTertiary)
                    Text("·")
                        .font(.micro)
                        .foregroundStyle(Color.textTertiary)
                    Text("\(merchant.count) txns")
                        .font(.micro)
                        .foregroundStyle(Color.textTertiary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(cat.color.opacity(0.15))
                            .frame(height: 3)
                        Capsule()
                            .fill(cat.color)
                            .frame(width: geo.size.width * pct, height: 3)
                    }
                }
                .frame(height: 3)
            }
            Text("₹\(compact(merchant.amount))")
                .font(.amount(14, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.md)
    }

    private func compact(_ amount: Decimal) -> String {
        let d = Double(truncating: amount as NSDecimalNumber)
        if d >= 1_00_000 { return String(format: "%.1fL", d / 1_00_000) }
        if d >= 1_000    { return String(format: "%.0fK", d / 1_000) }
        return String(format: "%.0f", d)
    }
}
