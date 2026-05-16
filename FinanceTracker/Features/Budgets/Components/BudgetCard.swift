import SwiftUI

struct BudgetCard: View {

    let budget: BudgetEntity
    @State private var animateProgress = false

    private var cat: CategoryEntity {
        CategoryEntity.find(slug: budget.categorySlug)
    }

    private var progressColor: Color {
        if budget.isOverBudget { return .expenseRed }
        if budget.isWarning    { return .warningAmber }
        return .incomeGreen
    }

    private var progressWidth: Double {
        min(budget.progress, 1.0)
    }

    private var progressPercent: Int {
        min(Int(budget.progress * 100), 999)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Top row: icon + name + period + amount
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(cat.color.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: cat.icon)
                        .font(.system(size: 22))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(cat.name)
                            .font(.titleMedium)
                            .foregroundColor(.textPrimary)

                        Spacer()

                        periodBadge
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("Spent")
                            .font(.micro)
                            .foregroundColor(.textSecondary)
                        Text(budget.spent.currencyString)
                            .font(Font.amount(13))
                            .fontWeight(.semibold)
                            .foregroundColor(.textPrimary)
                        Text("of")
                            .font(.micro)
                            .foregroundColor(.textSecondary)
                        Text(budget.amount.currencyString)
                            .font(Font.amount(13))
                            .foregroundColor(.textSecondary)
                    }
                }
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 8)

                        // Fill
                        RoundedRectangle(cornerRadius: 5)
                            .fill(progressColor)
                            .frame(
                                width: animateProgress
                                    ? geo.size.width * progressWidth
                                    : 0,
                                height: 8
                            )
                            .animation(.easeOut(duration: 0.7).delay(0.15), value: animateProgress)

                        // Over-budget overflow indicator
                        if budget.isOverBudget {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.expenseRed.opacity(0.3))
                                .frame(width: geo.size.width, height: 8)
                                .overlay(
                                    HStack(spacing: 3) {
                                        ForEach(0..<8, id: \.self) { _ in
                                            RoundedRectangle(cornerRadius: 1)
                                                .fill(Color.expenseRed)
                                                .frame(width: 2, height: 8)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 4)
                                )
                        }
                    }
                }
                .frame(height: 8)

                // Bottom row: remaining/over + percentage
                HStack {
                    if budget.isOverBudget {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.expenseRed)
                            Text("\(budget.remaining < 0 ? (-budget.remaining).currencyString : "₹0") over budget")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.expenseRed)
                        }
                    } else if budget.isWarning {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.warningAmber)
                            Text("\(budget.remaining.currencyString) remaining")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.warningAmber)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.incomeGreen)
                            Text("\(budget.remaining.currencyString) remaining")
                                .font(.caption)
                                .foregroundColor(.incomeGreen)
                        }
                    }

                    Spacer()

                    Text("\(progressPercent)%")
                        .font(Font.amount(12))
                        .fontWeight(.bold)
                        .foregroundColor(progressColor)
                }
            }
        }
        .padding(Spacing.base)
        .background(Color.bgCard)
        .cornerRadius(Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(progressColor.opacity(budget.isOverBudget || budget.isWarning ? 0.3 : 0), lineWidth: 1)
        )
        .onAppear {
            animateProgress = true
        }
        .onChange(of: budget.progress) { _, _ in
            animateProgress = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                animateProgress = true
            }
        }
    }

    private var periodBadge: some View {
        Text(budget.period.displayName)
            .font(.micro)
            .fontWeight(.semibold)
            .foregroundColor(.textSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.07))
            .cornerRadius(Radius.sm)
    }
}


#Preview {
    var b1 = BudgetEntity(categorySlug: "food", amount: 15000)
    b1.spent = 8400
    var b2 = BudgetEntity(categorySlug: "shopping", amount: 10000)
    b2.spent = 8800
    var b3 = BudgetEntity(categorySlug: "entertainment", amount: 3000)
    b3.spent = 4200
    return VStack(spacing: 16) {
        BudgetCard(budget: b1)
        BudgetCard(budget: b2)
        BudgetCard(budget: b3)
    }
    .padding()
    .background(Color.bgPrimary)
}
