import SwiftUI

// MARK: - PendingReviewBanner

struct PendingReviewBanner: View {

    let count: Int
    let onTap: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        if count > 0 {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
                onTap()
            }) {
                HStack(spacing: Spacing.md) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 36, height: 36)
                        Text("⚡")
                            .font(.system(size: 18))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(count) transaction\(count == 1 ? "" : "s") need your input")
                            .font(.titleMedium)
                            .foregroundColor(.white)

                        Text("Tap to review and confirm")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.75))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, Spacing.base)
                .padding(.vertical, Spacing.md)
                .background(
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(hex: "#FF9500"),
                                Color(hex: "#FF6B35")
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )

                        // Subtle shimmer overlay
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.clear,
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                .scaleEffect(isPressed ? 0.97 : 1.0)
                .shadow(
                    color: Color(hex: "#FF9500").opacity(0.35),
                    radius: 12,
                    x: 0,
                    y: 6
                )
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: count)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.bgPrimary.ignoresSafeArea()
        VStack(spacing: Spacing.base) {
            PendingReviewBanner(count: 3) {}
                .padding(.horizontal, Spacing.base)
            PendingReviewBanner(count: 1) {}
                .padding(.horizontal, Spacing.base)
            PendingReviewBanner(count: 0) {}
                .padding(.horizontal, Spacing.base)
        }
    }
}
