import SwiftUI

struct LockScreenView: View {
    var onUnlock: () -> Void

    @State private var isAuthenticating = false
    @State private var lastFailed = false

    private let biometric = BiometricAuthService.shared.availableBiometric

    var body: some View {
        ZStack {
            // Frosted backdrop so any glimpse behind it is unreadable
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: Spacing.xl) {
                Spacer()

                // App mark — mirrors onboarding logo
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.brandPrimary, .brandAccent, Color(hex: "#4338CA")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: .brandPrimary.opacity(0.4), radius: 16, x: 0, y: 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    Text("₹")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.white, .white.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                VStack(spacing: Spacing.sm) {
                    Text("FinanceTracker")
                        .font(.titleLarge)
                        .foregroundStyle(Color.textPrimary)
                    Text(lastFailed
                         ? "Authentication failed. Try again."
                         : "Unlock with \(biometric.displayName) to continue")
                        .font(.bodyMedium)
                        .foregroundStyle(lastFailed ? Color.expenseRed : Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xl)
                }

                Spacer()

                Button(action: { authenticate() }) {
                    HStack(spacing: Spacing.sm) {
                        if isAuthenticating {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Image(systemName: biometric.icon)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        Text(isAuthenticating ? "Unlocking…" : "Unlock with \(biometric.displayName)")
                            .font(.titleMedium)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.base)
                    .background(Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.full))
                }
                .buttonStyle(.plain)
                .disabled(isAuthenticating)
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
            }
        }
        .task {
            // Auto-trigger on appear so the user sees the system prompt immediately.
            authenticate()
        }
    }

    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task {
            let ok = await BiometricAuthService.shared.authenticate()
            isAuthenticating = false
            if ok {
                onUnlock()
            } else {
                lastFailed = true
            }
        }
    }
}
