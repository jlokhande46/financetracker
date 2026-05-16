import SwiftUI

struct SubscriptionSummaryCard: View {

    let subscriptions: [SubscriptionItem]
    @State private var isExpanded = false

    private let maxCollapsed = 4

    private var totalMonthly: Decimal {
        subscriptions.reduce(0) { $0 + $1.amount }
    }

    private var displayedItems: [SubscriptionItem] {
        isExpanded ? subscriptions : Array(subscriptions.prefix(maxCollapsed))
    }

    private var hasMore: Bool {
        subscriptions.count > maxCollapsed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SUBSCRIPTIONS")
                        .font(.micro)
                        .fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                        .kerning(1.2)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("Active plans")
                            .font(.titleMedium)
                            .foregroundColor(.textPrimary)
                        Text("·")
                            .foregroundColor(.textSecondary)
                        Text("\(totalMonthly.compactString)/mo")
                            .font(Font.amount(15))
                            .fontWeight(.semibold)
                            .foregroundColor(.brandPrimary)
                    }
                }
                Spacer()

                // Count badge
                Text("\(subscriptions.count)")
                    .font(.micro)
                    .fontWeight(.bold)
                    .foregroundColor(.brandPrimary)
                    .frame(width: 28, height: 28)
                    .background(Color.brandPrimary.opacity(0.15))
                    .clipShape(Circle())
            }

            // Subscription rows
            VStack(spacing: Spacing.sm) {
                ForEach(displayedItems) { sub in
                    subscriptionRow(sub)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.springy, value: isExpanded)

            Divider()
                .background(Color.white.opacity(0.08))

            // Total row
            HStack {
                Text("Monthly Total")
                    .font(.bodyMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(.textPrimary)

                Spacer()

                Text(totalMonthly.currencyString)
                    .font(Font.amount(15))
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
            }

            // Expand button
            if hasMore {
                Button(action: {
                    withAnimation(.springy) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack {
                        Text(isExpanded ? "Show less" : "See all \(subscriptions.count) subscriptions")
                            .font(.caption)
                            .foregroundColor(.brandPrimary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(.brandPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.brandPrimary.opacity(0.06))
                    .cornerRadius(Radius.sm)
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }

    private func subscriptionRow(_ sub: SubscriptionItem) -> some View {
        let cat = CategoryEntity.find(slug: sub.categorySlug)

        return HStack(spacing: Spacing.md) {
            // Icon circle
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(cat.color.opacity(0.18))
                    .frame(width: 40, height: 40)

                Image(systemName: cat.icon)
                    .font(.system(size: 18))
            }

            // Name + next date
            VStack(alignment: .leading, spacing: 3) {
                Text(sub.merchantName)
                    .font(.bodyMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)

                    Text("Monthly")
                        .font(.micro)
                        .foregroundColor(.textSecondary)

                    if let nextDate = sub.nextDate {
                        Text("· renews \(nextDate.dayMonthYear)")
                            .font(.micro)
                            .foregroundColor(.textSecondary)
                    }
                }
            }

            Spacer()

            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                Text(sub.amount.currencyString)
                    .font(Font.amount(14))
                    .fontWeight(.semibold)
                    .foregroundColor(.textPrimary)

                Text("/mo")
                    .font(.micro)
                    .foregroundColor(.textSecondary)
            }
        }
    }
}

#Preview {
    SubscriptionSummaryCard(subscriptions: [
        SubscriptionItem(merchantName: "Netflix", amount: 799, categorySlug: "entertainment", nextDate: Calendar.current.date(byAdding: .day, value: 12, to: Date())),
        SubscriptionItem(merchantName: "Spotify", amount: 119, categorySlug: "entertainment", nextDate: Calendar.current.date(byAdding: .day, value: 5, to: Date())),
        SubscriptionItem(merchantName: "Hotstar", amount: 299, categorySlug: "entertainment", nextDate: Calendar.current.date(byAdding: .day, value: 20, to: Date())),
        SubscriptionItem(merchantName: "iCloud+", amount: 75, categorySlug: "software", nextDate: Calendar.current.date(byAdding: .day, value: 8, to: Date())),
        SubscriptionItem(merchantName: "Notion", amount: 200, categorySlug: "software", nextDate: Calendar.current.date(byAdding: .day, value: 15, to: Date())),
    ])
    .padding()
    .background(Color.bgPrimary)
}
