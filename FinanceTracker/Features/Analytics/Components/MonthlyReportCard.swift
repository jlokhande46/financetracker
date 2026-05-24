import SwiftUI

/// A monthly "financial grade" card shown on Analytics below Net Worth.
/// Grades A-F based on: savings rate, budget adherence, and bill payment
/// timeliness. Designed to be a quick visual "are you doing well this month?"
struct MonthlyReportCard: View {
    let analysis: MonthlyAnalysis
    let budgetAdherence: Double
    let billsPaidOnTime: Double
    @AppStorage("hideAmounts") private var hideAmounts: Bool = false

    private var grade: (letter: String, color: Color, label: String) {
        let score = computeScore()
        switch score {
        case 90...100: return ("A", .incomeGreen, "Excellent")
        case 75..<90:  return ("B", Color(hex: "#22C55E"), "Good")
        case 60..<75:  return ("C", .warningAmber, "Fair")
        case 40..<60:  return ("D", Color(hex: "#F97316"), "Needs work")
        default:       return ("F", .expenseRed, "Critical")
        }
    }

    private func computeScore() -> Double {
        var score: Double = 0
        // Savings rate (max 40 points): 20%+ = full marks, linear down to 0
        let savingsContribution = min(40, max(0, analysis.savingsRate / 20 * 40))
        score += savingsContribution
        // Budget adherence (max 30 points): % of budgets within limit
        score += budgetAdherence * 30
        // Bills paid on time (max 30 points)
        score += billsPaidOnTime * 30
        return min(100, score)
    }

    private var spendChange: String {
        let pct = analysis.spendChangePercent
        if abs(pct) < 1 { return "Same as last month" }
        let dir = pct > 0 ? "↑" : "↓"
        return "\(dir) \(Int(abs(pct)))% vs last month"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MONTHLY REPORT")
                        .font(.micro)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textSecondary)
                        .kerning(1.2)
                    Text(analysis.month.shortMonthYear)
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                gradeCircle
            }

            HStack(spacing: Spacing.lg) {
                metric(label: "Savings Rate", value: String(format: "%.0f%%", analysis.savingsRate), target: "Target: 20%", hit: analysis.savingsRate >= 20)
                metric(label: "Budgets OK", value: String(format: "%.0f%%", budgetAdherence * 100), target: "Within limit", hit: budgetAdherence >= 0.8)
                metric(label: "Bills On-Time", value: String(format: "%.0f%%", billsPaidOnTime * 100), target: "Paid before due", hit: billsPaidOnTime >= 0.9)
            }

            HStack(spacing: Spacing.md) {
                Image(systemName: analysis.spendChangePercent <= 0 ? "arrow.down.right" : "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(analysis.spendChangePercent <= 0 ? Color.incomeGreen : Color.warningAmber)
                Text(spendChange)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("Score: \(Int(computeScore()))/100")
                    .font(.micro)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .cardStyle()
    }

    private var gradeCircle: some View {
        ZStack {
            Circle()
                .stroke(grade.color.opacity(0.2), lineWidth: 4)
                .frame(width: 56, height: 56)
            Circle()
                .trim(from: 0, to: computeScore() / 100)
                .stroke(grade.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 56, height: 56)
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(grade.letter)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(grade.color)
                Text(grade.label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(grade.color.opacity(0.8))
            }
        }
    }

    private func metric(label: String, value: String, target: String, hit: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: hit ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(hit ? Color.incomeGreen : Color.warningAmber)
                Text(label)
                    .font(.micro)
                    .foregroundStyle(Color.textSecondary)
            }
            Text(value)
                .font(.amount(16, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text(target)
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
