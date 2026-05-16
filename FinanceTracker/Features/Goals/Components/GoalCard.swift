import SwiftUI

struct GoalCard: View {
    let goal: GoalEntity
    let onTap: () -> Void
    let onAddContribution: () -> Void

    private var progressColor: Color {
        if goal.isCompleted { return Color.incomeGreen }
        return goal.type.color
    }

    private var formattedCurrent: String {
        formatINR(goal.currentAmount)
    }

    private var formattedTarget: String {
        formatINR(goal.targetAmount)
    }

    private var formattedMonthly: String? {
        guard let m = goal.monthlyRequired else { return nil }
        return formatINR(m)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.md) {

                // Header
                HStack(spacing: Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(goal.type.color.opacity(0.18))
                            .frame(width: 36, height: 36)
                        Image(systemName: goal.type.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(goal.type.color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.name)
                            .font(.titleMedium)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text(goal.type.displayName)
                            .font(.micro)
                            .foregroundStyle(Color.textTertiary)
                    }
                    Spacer()
                    if goal.isCompleted {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.incomeGreen)
                    }
                }

                // Progress ring + amounts
                HStack(spacing: Spacing.md) {
                    progressRing
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formattedCurrent)
                            .font(.amount(20, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                        Text("of \(formattedTarget)")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                }

                // Footer: monthly required or days remaining
                if let days = goal.daysRemaining, days > 0, !goal.isCompleted {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                        Text("\(days)d left")
                            .font(.micro)
                            .foregroundStyle(Color.textTertiary)
                        if let monthly = formattedMonthly {
                            Text("·")
                                .font(.micro)
                                .foregroundStyle(Color.textTertiary)
                            Text("\(monthly)/mo needed")
                                .font(.micro)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }

                // Contribute button
                if !goal.isCompleted {
                    Button(action: onAddContribution) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Add contribution")
                                .font(.caption)
                        }
                        .foregroundStyle(goal.type.color)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 6)
                        .background(goal.type.color.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.base)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(progressColor.opacity(0.15), lineWidth: 6)
                .frame(width: 56, height: 56)
            Circle()
                .trim(from: 0, to: goal.progressFraction)
                .stroke(progressColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 56, height: 56)
                .animation(.easeOut(duration: 0.6), value: goal.progressFraction)
            Text("\(Int(goal.progressFraction * 100))%")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.textPrimary)
        }
    }

    private func formatINR(_ amount: Decimal) -> String {
        let d = Double(truncating: amount as NSDecimalNumber)
        if d >= 1_00_00_000 { return String(format: "₹%.1fCr", d / 1_00_00_000) }
        if d >= 1_00_000    { return String(format: "₹%.1fL",  d / 1_00_000) }
        if d >= 1_000       { return String(format: "₹%.0fK",  d / 1_000) }
        return String(format: "₹%.0f", d)
    }
}
