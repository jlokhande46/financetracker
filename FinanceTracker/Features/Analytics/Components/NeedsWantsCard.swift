import SwiftUI

struct NeedsWantsBreakdown: Equatable {
    var needs: Decimal
    var wants: Decimal
    var savings: Decimal
    var total: Decimal { needs + wants + savings }

    func percent(_ intent: CategoryIntent) -> Double {
        guard total > 0 else { return 0 }
        let amount: Decimal
        switch intent {
        case .need:   amount = needs
        case .want:   amount = wants
        case .saving: amount = savings
        }
        return Double(truncating: (amount / total * 100) as NSDecimalNumber)
    }
}

struct NeedsWantsCard: View {
    let breakdown: NeedsWantsBreakdown

    private var topLine: String {
        let n = Int(breakdown.percent(.need).rounded())
        let w = Int(breakdown.percent(.want).rounded())
        let s = Int(breakdown.percent(.saving).rounded())
        return "\(n) / \(w) / \(s)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEEDS · WANTS · SAVINGS")
                        .font(.micro)
                        .foregroundStyle(Color.textSecondary)
                    Text("50/30/20 rule")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                Text(topLine)
                    .font(.amount(18, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
            }

            // Stacked bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    bar(for: .need,   width: geo.size.width)
                    bar(for: .want,   width: geo.size.width)
                    bar(for: .saving, width: geo.size.width)
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())

            // Legend
            HStack(spacing: Spacing.md) {
                ForEach(CategoryIntent.allCases) { intent in
                    legend(intent: intent)
                }
            }
        }
        .padding(Spacing.base)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func bar(for intent: CategoryIntent, width: CGFloat) -> some View {
        let fraction = max(0.02, breakdown.percent(intent) / 100.0)
        return intent.color
            .frame(width: width * CGFloat(fraction))
    }

    private func legend(intent: CategoryIntent) -> some View {
        let actual = Int(breakdown.percent(intent).rounded())
        let target = Int(intent.targetPercent)
        return HStack(spacing: 6) {
            Circle()
                .fill(intent.color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(intent.displayName)
                    .font(.micro)
                    .foregroundStyle(Color.textSecondary)
                Text("\(actual)% (target \(target)%)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(actual <= target + 5 ? Color.incomeGreen : Color.warningAmber)
            }
        }
    }
}
