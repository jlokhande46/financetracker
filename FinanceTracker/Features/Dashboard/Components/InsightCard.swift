import SwiftUI

struct InsightCard: View {

    let insight: InsightEntity
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isDismissing = false

    private var accentColor: Color {
        switch insight.type {
        case .warning:  return Color.warningAmber
        case .positive: return Color.incomeGreen
        case .tip:      return Color.brandPrimary
        case .neutral:  return Color.textSecondary
        }
    }

    private var iconName: String {
        switch insight.type {
        case .warning:  return "exclamationmark.triangle.fill"
        case .positive: return "checkmark.circle.fill"
        case .tip:      return "lightbulb.fill"
        case .neutral:  return "info.circle.fill"
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Card background
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Color.bgElevated)

            // Left accent border
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor)
                    .frame(width: 3)
                    .padding(.vertical, Spacing.md)
                Spacer()
            }

            // Content
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Top row: icon + title + dismiss
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: iconName)
                        .font(.system(size: 16))
                        .foregroundColor(accentColor)
                        .frame(width: 20)

                    Text(insight.title)
                        .font(.bodyMedium)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                // Body text
                Text(insight.body)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                // Amount badge (if present)
                if let amount = insight.amount {
                    HStack(spacing: 4) {
                        Text(amount.currencyString)
                            .font(Font.amount(13))
                            .fontWeight(.semibold)
                            .foregroundColor(accentColor)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 3)
                    .background(accentColor.opacity(0.12))
                    .cornerRadius(Radius.sm)
                }
            }
            .padding(.leading, Spacing.lg)
            .padding(.trailing, Spacing.md)
            .padding(.vertical, Spacing.md)
        }
        .frame(width: 280, height: 120, alignment: .topLeading)
        .clipped()
        .offset(x: dragOffset)
        .opacity(isDismissing ? 0 : (dragOffset < -60 ? 1 - Double(abs(dragOffset + 60) / 100) : 1))
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.width < 0 {
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    if value.translation.width < -80 {
                        dismiss()
                    } else {
                        withAnimation(.springy) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) {
            isDismissing = true
            dragOffset = -320
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}

// MARK: - Color extension

#Preview {
    ScrollView(.horizontal) {
        HStack(spacing: 12) {
            InsightCard(
                insight: InsightEntity(
                    id: UUID(),
                    type: .warning,
                    title: "Food spend up 42%",
                    body: "Your food category is significantly higher than last month. Consider reviewing dining expenses.",
                    amount: 14200,
                    categorySlug: "food",
                    date: Date(),
                    isRead: false
                ),
                onDismiss: {}
            )
            InsightCard(
                insight: InsightEntity(
                    id: UUID(),
                    type: .positive,
                    title: "Great savings this month!",
                    body: "You saved 36% of your income — ₹30.8K kept safe.",
                    amount: 30800,
                    categorySlug: nil,
                    date: Date(),
                    isRead: false
                ),
                onDismiss: {}
            )
            InsightCard(
                insight: InsightEntity(
                    id: UUID(),
                    type: .tip,
                    title: "Subscriptions cost ₹2.4K/mo",
                    body: "You have 5 active subscriptions. Review if all are still needed.",
                    amount: 2400,
                    categorySlug: "subscriptions",
                    date: Date(),
                    isRead: false
                ),
                onDismiss: {}
            )
        }
        .padding()
    }
    .background(Color.bgPrimary)
}
