import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {

    @Binding var hasOnboarded: Bool
    @State private var currentPage: Int = 0
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0
    @State private var particleAnimating: Bool = false

    private let totalPages = 4

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            // Background floating particles
            ParticleBackgroundView(animating: $particleAnimating)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar: Skip button (pages 0-2)
                HStack {
                    Spacer()
                    if currentPage < totalPages - 1 {
                        Button("Skip") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                hasOnboarded = true
                            }
                        }
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, Spacing.base)
                        .padding(.vertical, Spacing.sm)
                    }
                }
                .frame(height: 52)
                .padding(.horizontal, Spacing.base)

                // Page TabView
                TabView(selection: $currentPage) {
                    WelcomePage(logoScale: $logoScale, logoOpacity: $logoOpacity)
                        .tag(0)
                    HowItWorksPage()
                        .tag(1)
                    PrivacyPage()
                        .tag(2)
                    GetStartedPage {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            hasOnboarded = true
                        }
                    }
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // Bottom: page dots + Next button
                VStack(spacing: Spacing.xl) {
                    // Page dots
                    HStack(spacing: Spacing.sm) {
                        ForEach(0..<totalPages, id: \.self) { index in
                            Capsule()
                                .fill(index == currentPage ? Color.brandPrimary : Color.textSecondary.opacity(0.4))
                                .frame(width: index == currentPage ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.3), value: currentPage)
                        }
                    }

                    // Next button (pages 0-2)
                    if currentPage < totalPages - 1 {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                currentPage += 1
                            }
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Text("Next")
                                    .font(.titleMedium)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    colors: [.brandPrimary, .brandAccent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                        }
                        .padding(.horizontal, Spacing.base)
                    }
                }
                .padding(.bottom, Spacing.xxxl)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.2)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            particleAnimating = true
        }
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    @Binding var logoScale: CGFloat
    @Binding var logoOpacity: Double
    @State private var pulseAnim: Bool = false

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Animated logo
            ZStack {
                // Glow rings
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Color.brandPrimary.opacity(0.15 - Double(i) * 0.04), lineWidth: 1)
                        .frame(width: CGFloat(140 + i * 40), height: CGFloat(140 + i * 40))
                        .scaleEffect(pulseAnim ? 1.05 : 1.0)
                        .animation(
                            .easeInOut(duration: 2.0)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.3),
                            value: pulseAnim
                        )
                }

                // Main rounded-square — the new app icon proxy
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.brandPrimary, .brandAccent, Color(hex: "#4338CA")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(color: .brandPrimary.opacity(0.5), radius: 20, x: 0, y: 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1.5)
                    )

                // Stylised ₹ with a subtle offset shadow for depth
                Text("₹")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.white, .white.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 2)
            }
            .scaleEffect(logoScale)
            .opacity(logoOpacity)
            .onAppear { pulseAnim = true }

            VStack(spacing: Spacing.md) {
                Text("Smart Money Tracker")
                    .font(.displayLarge)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Track every rupee automatically.\nZero manual work.")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, Spacing.xl)

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Page 2: How It Works

private struct HowItWorksPage: View {
    @State private var appear: Bool = false

    private let features: [(emoji: String, title: String, description: String)] = [
        ("📨", "Connect Gmail", "Bank alerts auto-imported and categorized"),
        ("📄", "Upload Statements", "PDF statements parsed in seconds"),
        ("✨", "Smart Categories", "AI categorizes everything, you review edge cases")
    ]

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            VStack(spacing: Spacing.md) {
                Text("How it works")
                    .font(.titleLarge)
                    .foregroundColor(.textPrimary)
                Text("Three simple steps to financial clarity")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, Spacing.xl)

            VStack(spacing: Spacing.base) {
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    FeatureRow(emoji: feature.emoji, title: feature.title, description: feature.description)
                        .opacity(appear ? 1 : 0)
                        .offset(x: appear ? 0 : 40)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.12),
                            value: appear
                        )
                }
            }
            .padding(.horizontal, Spacing.base)

            Spacer()
            Spacer()
        }
        .onAppear { appear = true }
        .onDisappear { appear = false }
    }
}

private struct FeatureRow: View {
    let emoji: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: Spacing.base) {
            ZStack {
                Circle()
                    .fill(Color.brandPrimary.opacity(0.15))
                    .frame(width: 52, height: 52)
                Text(emoji)
                    .font(.system(size: 24))
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.titleMedium)
                    .foregroundColor(.textPrimary)
                Text(description)
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(Spacing.base)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }
}

// MARK: - Page 3: Privacy First

private struct PrivacyPage: View {
    @State private var shieldScale: CGFloat = 0.7
    @State private var appear: Bool = false

    private let bullets = [
        ("lock.fill", "End-to-end encrypted"),
        ("hand.raised.fill", "No data sold"),
        ("iphone.and.arrow.forward", "Local-first storage")
    ]

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Shield icon
            ZStack {
                Circle()
                    .fill(Color.incomeGreen.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: "shield.fill")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.incomeGreen, .incomeGreen.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .scaleEffect(shieldScale)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    shieldScale = 1.0
                }
                appear = true
            }

            VStack(spacing: Spacing.md) {
                Text("Your data stays yours")
                    .font(.titleLarge)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)

                Text("We believe privacy is a right, not a feature.")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xl)

            VStack(spacing: Spacing.md) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { index, bullet in
                    HStack(spacing: Spacing.base) {
                        Image(systemName: bullet.0)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.incomeGreen)
                            .frame(width: 32)

                        Text(bullet.1)
                            .font(.bodyMedium)
                            .foregroundColor(.textPrimary)

                        Spacer()
                    }
                    .padding(.horizontal, Spacing.xl)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 20)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.1 + 0.2),
                        value: appear
                    )
                }
            }

            Spacer()
            Spacer()
        }
        .onDisappear { appear = false }
    }
}

// MARK: - Page 4: Get Started

private struct GetStartedPage: View {
    let onGetStarted: () -> Void
    @State private var appear: Bool = false

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Checkmark circle
            ZStack {
                Circle()
                    .fill(Color.brandPrimary.opacity(0.15))
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.brandPrimary, .brandAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(appear ? 1.0 : 0.6)
            .opacity(appear ? 1 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: appear)

            VStack(spacing: Spacing.md) {
                Text("You're all set!")
                    .font(.displayLarge)
                    .foregroundColor(.textPrimary)

                Text("Your smart finance companion is ready.\nStart by importing a bank statement or let us auto-detect your transactions.")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, Spacing.xl)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 20)
            .animation(.spring(response: 0.5).delay(0.15), value: appear)

            Spacer()

            VStack(spacing: Spacing.md) {
                // Primary CTA
                Button(action: onGetStarted) {
                    Text("Get Started")
                        .font(.titleMedium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: [.brandPrimary, .brandAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                }

                // Secondary CTA
                Button(action: onGetStarted) {
                    Text("Import a statement first")
                        .font(.bodyMedium)
                        .foregroundColor(.brandPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.lg)
                                .stroke(Color.brandPrimary.opacity(0.5), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, Spacing.base)
            .padding(.bottom, Spacing.xl)
            .opacity(appear ? 1 : 0)
            .animation(.spring(response: 0.5).delay(0.25), value: appear)
        }
        .onAppear { appear = true }
        .onDisappear { appear = false }
    }
}

// MARK: - Particle Background

private struct ParticleBackgroundView: View {
    @Binding var animating: Bool

    private struct Particle: Identifiable {
        let id = UUID()
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: Double
        let speed: Double
    }

    private let particles: [Particle] = (0..<20).map { _ in
        Particle(
            x: CGFloat.random(in: 0...1),
            y: CGFloat.random(in: 0...1),
            size: CGFloat.random(in: 2...6),
            opacity: Double.random(in: 0.05...0.2),
            speed: Double.random(in: 3...8)
        )
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(particles) { p in
                Circle()
                    .fill(Color.brandPrimary)
                    .frame(width: p.size, height: p.size)
                    .opacity(animating ? p.opacity : 0)
                    .position(
                        x: p.x * geo.size.width,
                        y: animating
                            ? p.y * geo.size.height - 60
                            : p.y * geo.size.height
                    )
                    .animation(
                        .easeInOut(duration: p.speed)
                        .repeatForever(autoreverses: true),
                        value: animating
                    )
            }
        }
    }
}
