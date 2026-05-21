import SwiftUI

/// Horizontal credit-card card for the Dashboard "My Cards" section.
/// Always shown for every credit account regardless of statement status.
/// When an unpaid `CardStatement` exists for the card, surfaces the
/// outstanding total + a Mark-Paid button inline.
struct CardCycleCard: View {
    let account: AccountEntity
    let unpaidStatement: CardStatementEntity?
    var onMarkPaid: () -> Void = {}
    var onTap: () -> Void = {}

    @AppStorage("hideAmounts") private var hideAmounts: Bool = false

    private var accentColor: Color { Color(hex: account.colorHex) }

    // Outstanding shown on the card. Prefers the unpaid statement total when
    // present (it's the authoritative billed amount); otherwise falls back to
    // the running account balance.
    private var outstanding: Decimal {
        unpaidStatement?.totalDue ?? account.balance
    }

    private var outstandingLabel: String {
        unpaidStatement != nil ? "Total Due" : "Outstanding"
    }

    // Next bill / due occurrence relative to today, ignoring whether the
    // statement has already been generated this cycle. Cosmetic only — the
    // BillCycleManager owns the actual cycle math.
    private struct NextDay {
        let day: Int
        let date: Date
        let daysFromNow: Int
    }

    private func nextOccurrence(of day: Int) -> NextDay {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month], from: now)
        comps.day = day
        let thisMonth = cal.date(from: comps) ?? now
        let target = thisMonth >= cal.startOfDay(for: now)
            ? thisMonth
            : (cal.date(byAdding: .month, value: 1, to: thisMonth) ?? thisMonth)
        let daysFromNow = cal.dateComponents([.day],
                                             from: cal.startOfDay(for: now),
                                             to: cal.startOfDay(for: target)).day ?? 0
        return NextDay(day: day, date: target, daysFromNow: daysFromNow)
    }

    private func countdown(_ days: Int) -> String {
        switch days {
        case 0:      return "Today"
        case 1:      return "Tomorrow"
        default:     return "in \(days)d"
        }
    }

    private func urgency(_ days: Int) -> Color {
        if days <= 0 { return .expenseRed }
        if days <= 3 { return .warningAmber }
        return .textSecondary
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                header
                outstandingBlock
                Divider().background(Color.white.opacity(0.08))
                cycleRow
                if let stmt = unpaidStatement {
                    markPaidButton(for: stmt)
                }
            }
            .padding(Spacing.base)
            .frame(width: 240, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [accentColor.opacity(0.22), Color.bgCard],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(accentColor.opacity(0.30), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(accentColor.opacity(0.25))
                    .frame(width: 32, height: 32)
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(account.name)
                    .font(.bodyMedium)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let last4 = account.last4 {
                    Text("•••• \(last4)")
                        .font(.micro)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var outstandingBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(outstandingLabel.uppercased())
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
            Text(outstanding.currencyString(hidden: hideAmounts))
                .font(.amount(22, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            if let limit = account.creditLimit, !hideAmounts, limit > 0 {
                let pct = min(100, Int(Double(truncating: (account.balance / limit * 100) as NSDecimalNumber).rounded()))
                Text("\(pct)% of \(limit.compactString) limit")
                    .font(.micro)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    private var cycleRow: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            cycleColumn(
                label: "BILL",
                icon: "doc.text.fill",
                day: account.statementDay
            )
            Spacer(minLength: 0)
            cycleColumn(
                label: "DUE",
                icon: "exclamationmark.triangle.fill",
                day: account.dueDay
            )
        }
    }

    @ViewBuilder
    private func cycleColumn(label: String, icon: String, day: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textSecondary)
                Text(label)
                    .font(.micro)
                    .foregroundStyle(Color.textSecondary)
            }
            if let day {
                let next = nextOccurrence(of: day)
                Text(ordinal(day))
                    .font(.amount(15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(countdown(next.daysFromNow))
                    .font(.micro)
                    .foregroundStyle(urgency(next.daysFromNow))
            } else {
                Text("Not set")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    private func markPaidButton(for statement: CardStatementEntity) -> some View {
        let urgency = Color(hex: statement.urgencyColor)
        let label: String = {
            let d = statement.daysUntilDue
            if d < 0  { return "Mark Paid · Overdue \(-d)d" }
            if d == 0 { return "Mark Paid · Due Today" }
            return "Mark Paid · Due in \(d)d"
        }()
        return Button(action: onMarkPaid) {
            Text(label)
                .font(.micro)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(urgency)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func ordinal(_ day: Int) -> String {
        let suffix: String
        switch day % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }
}
