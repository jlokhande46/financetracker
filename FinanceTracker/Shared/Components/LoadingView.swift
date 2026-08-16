import SwiftUI

// MARK: - LoadingView

/// Small three-dot pulse used for inline / overlay loading states.
///
/// The animation is driven declaratively by a single `repeatForever` per dot,
/// staggered with `.delay`. It deliberately does NOT use `DispatchQueue`
/// recursion: the previous implementation had every dot re-arm the whole
/// cycle, so each pass scheduled three restarts, each of which scheduled three
/// more — 3^n timers. A loader left on screen for a few seconds queued tens of
/// thousands of closures onto the main queue, each firing a `withAnimation`
/// over `@State` arrays. Declarative animation also stops on its own when the
/// view unmounts, so there's no teardown flag to get wrong.
struct LoadingView: View {

    @State private var animating: Bool = false

    private let dotCount = 3
    private let dotSize: CGFloat = 10

    var body: some View {
        VStack(spacing: Spacing.base) {
            HStack(spacing: Spacing.md) {
                ForEach(0..<dotCount, id: \.self) { index in
                    Circle()
                        .fill(Color.brandPrimary)
                        .frame(width: dotSize, height: dotSize)
                        .scaleEffect(animating ? 1.4 : 1.0)
                        .opacity(animating ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                            value: animating
                        )
                }
            }

            Text("Loading…")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { animating = true }
    }
}

// MARK: - AppLaunchView

/// Cold-start screen shown while the DI container and view models spin up.
///
/// Deliberately mirrors the static launch screen (same `LaunchBackground`
/// colour, same gradient ₹ mark as the app icon and onboarding) so the handoff
/// from the system launch image into SwiftUI reads as one continuous screen
/// rather than a flash into a different-looking loader.
struct AppLaunchView: View {

    @State private var appeared = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: Spacing.xl) {
                ZStack {
                    // Soft halo that breathes behind the mark.
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(Color.brandPrimary.opacity(0.18))
                        .frame(width: 132, height: 132)
                        .scaleEffect(pulse ? 1.08 : 0.94)
                        .opacity(pulse ? 0.9 : 0.45)
                        .blur(radius: 12)

                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.brandPrimary, .brandAccent, Color(hex: "#4338CA")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 108, height: 108)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1.5)
                        )
                        .shadow(color: .brandPrimary.opacity(0.45), radius: 22, y: 10)
                        .overlay(
                            Text("₹")
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    .linearGradient(
                                        colors: [.white, .white.opacity(0.85)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 2)
                        )
                }
                .scaleEffect(appeared ? 1 : 0.88)
                .opacity(appeared ? 1 : 0)

                Text("FinanceTracker")
                    .font(.titleMedium)
                    .foregroundStyle(Color.textPrimary)
                    .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Loading Overlay Modifier

struct LoadingOverlay: ViewModifier {
    let isLoading: Bool

    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(isLoading)
                .blur(radius: isLoading ? 2 : 0)
                .animation(.easeInOut(duration: 0.2), value: isLoading)

            if isLoading {
                ZStack {
                    Color.bgPrimary.opacity(0.6)
                        .ignoresSafeArea()

                    LoadingView()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isLoading)
    }
}

extension View {
    /// Adds a full-screen loading overlay when `isLoading` is true.
    func loadingOverlay(_ isLoading: Bool) -> some View {
        modifier(LoadingOverlay(isLoading: isLoading))
    }
}

// MARK: - Preview

#Preview("Inline loader") {
    ZStack {
        Color.bgPrimary.ignoresSafeArea()
        LoadingView()
    }
}

#Preview("Cold start") {
    AppLaunchView()
}
