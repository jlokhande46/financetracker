import SwiftUI

// MARK: - ToastType

enum ToastType {
    case success
    case error
    case info

    var iconName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error:   return "xmark.circle.fill"
        case .info:    return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: return .incomeGreen
        case .error:   return .expenseRed
        case .info:    return .brandPrimary
        }
    }

    var backgroundColor: Color {
        switch self {
        case .success: return Color.incomeGreen.opacity(0.15)
        case .error:   return Color.expenseRed.opacity(0.15)
        case .info:    return Color.brandPrimary.opacity(0.15)
        }
    }
}

// MARK: - ToastView

private struct ToastView: View {
    let message: String
    let type: ToastType

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: type.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(type.color)

            Text(message)
                .font(.bodyMedium)
                .foregroundColor(.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.md)
        .background(
            ZStack {
                // Frosted glass effect using blurred backdrop
                RoundedRectangle(cornerRadius: Radius.full)
                    .fill(Color.bgElevated)

                RoundedRectangle(cornerRadius: Radius.full)
                    .fill(type.backgroundColor)

                RoundedRectangle(cornerRadius: Radius.full)
                    .stroke(type.color.opacity(0.3), lineWidth: 1)
            }
        )
        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 6)
    }
}

// MARK: - ToastModifier

struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let type: ToastType
    let duration: TimeInterval

    @State private var workItem: DispatchWorkItem?

    init(isPresented: Binding<Bool>, message: String, type: ToastType, duration: TimeInterval = 2.0) {
        self._isPresented = isPresented
        self.message = message
        self.type = type
        self.duration = duration
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isPresented {
                    ToastView(message: message, type: type)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.bottom, 24)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            )
                        )
                        .zIndex(999)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isPresented)
            .onChange(of: isPresented) { _, newValue in
                if newValue {
                    scheduleAutoDismiss()
                }
            }
    }

    private func scheduleAutoDismiss() {
        workItem?.cancel()
        let item = DispatchWorkItem {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isPresented = false
            }
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }
}

// MARK: - View Extension

extension View {
    /// Attaches a toast notification that auto-dismisses after 2 seconds.
    func toast(
        isPresented: Binding<Bool>,
        message: String,
        type: ToastType = .info,
        duration: TimeInterval = 2.0
    ) -> some View {
        modifier(ToastModifier(isPresented: isPresented, message: message, type: type, duration: duration))
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.bgPrimary.ignoresSafeArea()

        VStack(spacing: Spacing.base) {
            ToastView(message: "Transaction added successfully", type: .success)
            ToastView(message: "Import failed: file not readable", type: .error)
            ToastView(message: "3 transactions need your review", type: .info)
        }
        .padding()
    }
}
