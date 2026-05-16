import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var action: (() -> Void)? = nil
    var actionTitle: String = ""

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(Color.textTertiary)
                .padding(.bottom, Spacing.sm)

            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(.titleMedium)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            if let action = action, !actionTitle.isEmpty {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.titleMedium)
                        .foregroundStyle(.white)
                        .frame(maxWidth: 200)
                        .padding(.vertical, Spacing.md)
                        .background(Color.brandPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.full))
                }
                .padding(.top, Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.xxl)
    }
}

#Preview {
    ZStack {
        Color.bgPrimary.ignoresSafeArea()
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No transactions found",
            subtitle: "Try adjusting your search or filters to find what you're looking for.",
            action: {},
            actionTitle: "Clear Filters"
        )
    }
}
