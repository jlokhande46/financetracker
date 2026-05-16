import SwiftUI

// MARK: - LoadingView

struct LoadingView: View {

    @State private var dotOpacities: [Double] = [0.3, 0.3, 0.3]
    @State private var dotScales: [CGFloat] = [1.0, 1.0, 1.0]
    @State private var animating: Bool = false

    private let dotCount = 3
    private let dotSize: CGFloat = 10
    private let animationDuration: Double = 0.5
    private let delayStep: Double = 0.15

    var body: some View {
        VStack(spacing: Spacing.base) {
            HStack(spacing: Spacing.md) {
                ForEach(0..<dotCount, id: \.self) { index in
                    Circle()
                        .fill(Color.brandPrimary)
                        .frame(width: dotSize, height: dotSize)
                        .scaleEffect(dotScales[index])
                        .opacity(dotOpacities[index])
                }
            }

            Text("Loading…")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            animating = false
        }
    }

    private func startAnimation() {
        animating = true
        animateDot(index: 0)
    }

    private func animateDot(index: Int) {
        guard animating else { return }

        withAnimation(
            .easeInOut(duration: animationDuration)
        ) {
            dotOpacities[index] = 1.0
            dotScales[index] = 1.4
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            guard animating else { return }
            withAnimation(.easeInOut(duration: animationDuration)) {
                dotOpacities[index] = 0.3
                dotScales[index] = 1.0
            }
        }

        // Trigger next dot
        let nextIndex = index + 1
        if nextIndex < dotCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + delayStep) {
                guard animating else { return }
                animateDot(index: nextIndex)
            }
        }

        // Loop: restart after all dots complete
        let loopDelay = Double(dotCount) * delayStep + animationDuration * 2
        DispatchQueue.main.asyncAfter(deadline: .now() + loopDelay) {
            guard animating else { return }
            animateDot(index: 0)
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

#Preview {
    ZStack {
        Color.bgPrimary.ignoresSafeArea()
        LoadingView()
    }
}
