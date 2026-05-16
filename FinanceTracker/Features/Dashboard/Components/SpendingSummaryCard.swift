import SwiftUI

struct SpendingSummaryCard: View {

    let analysis: MonthlyAnalysis
    @State private var animateProgress = false
    @State private var animateNumbers = false

    private var progress: Double {
        guard analysis.totalIncome > 0 else { return 0 }
        return min(Double(truncating: (analysis.totalExpenses / analysis.totalIncome) as NSDecimalNumber), 1.0)
    }

    private var progressColor: Color {
        if progress < 0.7 { return .incomeGreen }
        if progress < 0.9 { return .warningAmber }
        return .expenseRed
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.brandPrimary.opacity(0.25),
                    Color.bgCard
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .cornerRadius(Radius.xl)

            // Decorative circle
            Circle()
                .fill(Color.brandPrimary.opacity(0.08))
                .frame(width: 180, height: 180)
                .offset(x: 220, y: -40)
                .blur(radius: 20)

            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Header label
                Text("SPENT THIS MONTH")
                    .font(.micro)
                    .fontWeight(.semibold)
                    .foregroundColor(.textSecondary.opacity(0.8))
                    .kerning(1.5)

                // Main amount
                Text(animateNumbers ? analysis.totalExpenses.currencyString : "₹0")
                    .font(Font.amount(40))
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.springy, value: animateNumbers)

                // Progress bar
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(progressColor)
                                .frame(
                                    width: animateProgress ? geo.size.width * progress : 0,
                                    height: 6
                                )
                                .animation(.easeOut(duration: 0.8).delay(0.2), value: animateProgress)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text(String(format: "%.0f%% of income used", progress * 100))
                            .font(.micro)
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text(analysis.totalIncome.currencyString)
                            .font(.micro)
                            .foregroundColor(.textSecondary)
                    }
                }

                // Bottom stats row
                HStack(spacing: 0) {
                    // Income
                    statItem(
                        label: "Income",
                        value: analysis.totalIncome.compactString,
                        icon: "arrow.down.circle.fill",
                        color: .incomeGreen
                    )

                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1, height: 40)
                        .padding(.horizontal, Spacing.lg)

                    // Savings
                    savingsItem
                }
                .padding(.top, Spacing.xs)
            }
            .padding(Spacing.xl)
        }
        .shadow(color: .brandPrimary.opacity(0.15), radius: 20, x: 0, y: 8)
        .onAppear {
            withAnimation { animateNumbers = true }
            animateProgress = true
        }
        .onChange(of: analysis.totalExpenses) { _, _ in
            animateNumbers = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation { animateNumbers = true }
            }
        }
    }

    private func statItem(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Text(label)
                    .font(.micro)
                    .foregroundColor(.textSecondary)
            }
            Text("₹\(value)")
                .font(Font.amount(18))
                .fontWeight(.semibold)
                .foregroundColor(.textPrimary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var savingsItem: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(analysis.savings >= 0 ? .incomeGreen : .expenseRed)
                Text("Savings")
                    .font(.micro)
                    .foregroundColor(.textSecondary)
            }

            HStack(alignment: .bottom, spacing: 4) {
                Text("₹\((analysis.savings < 0 ? -analysis.savings : analysis.savings).compactString)")
                    .font(Font.amount(18))
                    .fontWeight(.semibold)
                    .foregroundColor(analysis.savings >= 0 ? .textPrimary : .expenseRed)
                    .contentTransition(.numericText())

                if analysis.savingsRate != 0 {
                    Text(String(format: "%.0f%%", abs(analysis.savingsRate)))
                        .font(.micro)
                        .fontWeight(.semibold)
                        .foregroundColor(analysis.savings >= 0 ? .incomeGreen : .expenseRed)
                        .padding(.bottom, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview
#Preview {
    SpendingSummaryCard(analysis: MonthlyAnalysis(
        month: Date(),
        totalIncome: 85000,
        totalExpenses: 54200,
        savings: 30800,
        savingsRate: 36.2,
        categoryBreakdown: [],
        topMerchants: [],
        subscriptions: [],
        dayWiseSpend: [],
        previousMonthExpenses: 48000,
        spendChangePercent: 12.9
    ))
    .padding()
    .background(Color.bgPrimary)
}
