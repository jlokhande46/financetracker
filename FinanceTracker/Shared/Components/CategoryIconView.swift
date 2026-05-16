import SwiftUI

struct CategoryIconView: View {
    let slug: String
    var size: CGFloat = 36
    var isSelected: Bool = false

    private var category: CategoryEntity {
        CategoryEntity.find(slug: slug)
    }

    private var iconSize: CGFloat { size * 0.5 }

    var body: some View {
        ZStack {
            Circle()
                .fill(category.color.opacity(0.18))
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.brandPrimary : Color.clear,
                            lineWidth: isSelected ? 2 : 0
                        )
                )

            Image(systemName: category.icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(category.color)
        }
        .animation(.springy, value: isSelected)
    }
}

// MARK: - Merchant Initial Fallback
struct MerchantIconView: View {
    let name: String
    var size: CGFloat = 36

    private var initial: String {
        String(name.prefix(1)).uppercased()
    }

    private var backgroundColor: Color {
        let colors: [Color] = [.brandPrimary, .incomeGreen, .warningAmber, .expenseRed, .catTravel, .catShopping]
        let index = abs(name.hashValue) % colors.count
        return colors[index]
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor.opacity(0.2))
                .frame(width: size, height: size)

            Text(initial)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(backgroundColor)
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        CategoryIconView(slug: "food", size: 44)
        CategoryIconView(slug: "travel", size: 44, isSelected: true)
        CategoryIconView(slug: "shopping", size: 44)
        CategoryIconView(slug: "unknown_slug", size: 44)
        MerchantIconView(name: "Swiggy", size: 44)
    }
    .padding()
    .background(Color.bgPrimary)
}
