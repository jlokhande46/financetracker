import SwiftUI

extension View {
    func cardStyle(padding: CGFloat = Spacing.base) -> some View {
        self
            .padding(padding)
            .background(Color.bgCard)
            .cornerRadius(Radius.lg)
    }

    func elevatedCardStyle() -> some View {
        self
            .padding(Spacing.base)
            .background(Color.bgElevated)
            .cornerRadius(Radius.lg)
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)
            self
        }
    }

    func shimmerEffect(isLoading: Bool) -> some View {
        self.redacted(reason: isLoading ? .placeholder : [])
    }
}

extension Animation {
    static let springy = Animation.spring(response: 0.35, dampingFraction: 0.7)
    static let smooth = Animation.easeInOut(duration: 0.25)
}
