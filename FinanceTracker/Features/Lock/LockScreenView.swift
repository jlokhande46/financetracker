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

                // App lock icon
                ZStack {
                    Circle()
                        .fill(Color.brandPrimary.opacity(0.15))
                        .frame(width: 120, height: 120)
                    Image(systemName: biometric.icon)
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(Color.brandPrimary)
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
