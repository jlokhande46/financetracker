import SwiftUI

/// Heuristic-driven insights surfaced on the Dashboard.
/// No ML model — just rules over the user's actual spend, goals, and the 50/30/20 frame.
struct SmartInsight: Identifiable, Equatable {
    let id: UUID = UUID()
    var icon: String
    var iconColor: Color
    var headline: String
    var detail: String
    var actionLabel: String?
}

struct SmartInsightsCard: View {
    let insights: [SmartInsight]

    var body: some View {
        if insights.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.brandAccent)
                    Text("SMART INSIGHTS")
                        .font(.micro)
                        .foregroundStyle(Color.textSecondary)
                        .kerning(1.2)
                }
                .padding(.horizontal, Spacing.base)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(insights) { insight in
                            insightCard(insight)
                        }
                    }
                    .padding(.horizontal, Spacing.base)
                }
            }
        }
    }

    private func insightCard(_ insight: SmartInsight) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(insight.iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: insight.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(insight.iconColor)
            }
            Text(insight.headline)
                .font(.titleMedium)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
            Text(insight.detail)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let action = insight.actionLabel {
                Text(action)
                    .font(.micro)
                    .foregroundStyle(insight.iconColor)
                    .padding(.top, 2)
            }
        }
        .padding(Spacing.base)
        .frame(width: 240, alignment: .leading)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(insight.iconColor.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Generator

enum SmartInsightsEngine {

    /// `transactions` is the CURRENT month's debits/credits.
    /// `historicalTransactions` is the trailing 3-6 months used for anomaly detection
    /// and recurring-transaction discovery.
    static func generate(
        transactions: [TransactionEntity],
        historicalTransactions: [TransactionEntity] = [],
        goals: [GoalEntity],
        monthlyIncome: Decimal
    ) -> [SmartInsight] {
        var out: [SmartInsight] = []

        let expenses = transactions.filter { $0.isDebit }
        let totalSpend = expenses.reduce(Decimal(0)) { $0 + $1.amount }

        // 1. 50/30/20 imbalance insight
        if totalSpend > 0 {
            var byIntent: [CategoryIntent: Decimal] = [:]
            for t in expenses {
                guard let intent = t.effectiveIntent else { continue }
                byIntent[intent, default: 0] += t.amount
            }

            let wants = byIntent[.want] ?? 0
            let wantsPct = Double(truncating: (wants / totalSpend * 100) as NSDecimalNumber)
            if wantsPct > 35 {
                let excess = wants - (totalSpend * Decimal(0.30))
                out.append(SmartInsight(
                    icon: "sparkles",
                    iconColor: Color(hex: "#F59E0B"),
                    headline: "Wants ~\(Int(wantsPct))% of spend",
                    detail: "Trim ~\(formatINR(excess)) to hit the 30% target. That money can flow into goals.",
                    actionLabel: nil
                ))
            }

            let savings = byIntent[.saving] ?? 0
            let savingsPct = totalSpend > 0 ? Double(truncating: (savings / totalSpend * 100) as NSDecimalNumber) : 0
            if savingsPct < 10 {
                out.append(SmartInsight(
                    icon: "leaf.fill",
                    iconColor: Color(hex: "#10B981"),
                    headline: "Savings rate is low",
                    detail: "You're saving only \(Int(savingsPct))% this month. Aim for 20% to compound faster.",
                    actionLabel: nil
                ))
            }
        }

        // 2. Top category to cut
        let byCategory = Dictionary(grouping: expenses, by: { $0.categorySlug })
            .mapValues { $0.reduce(Decimal(0)) { $0 + $1.amount } }
        let wantsCategories = byCategory.filter { slug, _ in
            CategoryEntity.find(slug: slug).intent == .want
        }
        if let top = wantsCategories.max(by: { $0.value < $1.value }), top.value > 0 {
            let cat = CategoryEntity.find(slug: top.key)
            out.append(SmartInsight(
                icon: cat.icon,
                iconColor: cat.color,
                headline: "\(cat.name) tops your wants",
                detail: "\(formatINR(top.value)) this month. A 20% cut frees \(formatINR(top.value * Decimal(0.2)))/mo.",
                actionLabel: nil
            ))
        }

        // 3. Goal projections
        let monthlyDisposable = max(Decimal(0), monthlyIncome - totalSpend)
        for goal in goals.prefix(3) where !goal.isCompleted {
            // If a target date is set, compare current pace vs required pace
            if let monthlyNeeded = goal.monthlyRequired {
                if monthlyDisposable >= monthlyNeeded {
                    out.append(SmartInsight(
                        icon: goal.type.icon,
                        iconColor: goal.type.color,
                        headline: "\(goal.name): on track",
                        detail: "You need \(formatINR(monthlyNeeded))/mo. At current saving pace, you'll hit it by the target date.",
                        actionLabel: nil
                    ))
                } else {
                    let shortfall = monthlyNeeded - monthlyDisposable
                    out.append(SmartInsight(
                        icon: "exclamationmark.triangle.fill",
                        iconColor: Color(hex: "#EF4444"),
                        headline: "\(goal.name): short by \(formatINR(shortfall))/mo",
                        detail: "Goal needs \(formatINR(monthlyNeeded))/mo; current pace can spare \(formatINR(monthlyDisposable))/mo.",
                        actionLabel: nil
                    ))
                }
            } else if monthlyDisposable > 0 {
                // No target date — estimate months at current pace
                let monthsToHit = Double(truncating: (goal.remaining / monthlyDisposable) as NSDecimalNumber)
                if monthsToHit.isFinite && monthsToHit > 0 {
                    let months = Int(monthsToHit.rounded(.up))
                    out.append(SmartInsight(
                        icon: goal.type.icon,
                        iconColor: goal.type.color,
                        headline: "\(goal.name) in ~\(months) months",
                        detail: "At your current saving pace of \(formatINR(monthlyDisposable))/mo, you'll hit \(formatINR(goal.targetAmount)) in about \(months) months.",
                        actionLabel: nil
                    ))
                }
            }
        }

        // 4. Subscription review hint
        let subs = expenses.filter { $0.categorySlug == "subscriptions" }
        if subs.count >= 3 {
            let subTotal = subs.reduce(Decimal(0)) { $0 + $1.amount }
            out.append(SmartInsight(
                icon: "repeat",
                iconColor: Color(hex: "#EC4899"),
                headline: "\(subs.count) subscriptions this month",
                detail: "Costing \(formatINR(subTotal)). Audit them — one unused = pure savings.",
                actionLabel: nil
            ))
        }

        // 5. Anomaly detection — z-score on category spend vs trailing history.
        //    Per category, compare this month against mean/stddev of prior months.
        //    Flag the category with the strongest "above-normal" deviation.
        if !historicalTransactions.isEmpty {
            let cal = Calendar.current
            let monthsBack = Dictionary(grouping: historicalTransactions.filter { $0.isDebit }) { txn -> Date in
                let comps = cal.dateComponents([.year, .month], from: txn.date)
                return cal.date(from: comps) ?? txn.date
            }
            // Build {categorySlug: [monthlyTotal, ...]} for the historical months.
            var monthlyByCategory: [String: [Decimal]] = [:]
            for (_, txns) in monthsBack {
                let perCat = Dictionary(grouping: txns, by: { $0.categorySlug })
                    .mapValues { $0.reduce(Decimal(0)) { $0 + $1.amount } }
                for (slug, total) in perCat {
                    monthlyByCategory[slug, default: []].append(total)
                }
            }
            let thisMonthByCategory = Dictionary(grouping: expenses, by: { $0.categorySlug })
                .mapValues { $0.reduce(Decimal(0)) { $0 + $1.amount } }

            var strongestAnomaly: (slug: String, current: Decimal, mean: Decimal, z: Double)?
            for (slug, history) in monthlyByCategory where history.count >= 2 {
                let current = thisMonthByCategory[slug] ?? 0
                guard current > 0 else { continue }
                let nums = history.map { Double(truncating: $0 as NSDecimalNumber) }
                let mean = nums.reduce(0, +) / Double(nums.count)
                let variance = nums.map { pow($0 - mean, 2) }.reduce(0, +) / Double(nums.count)
                let stddev = sqrt(variance)
                guard stddev > 1 else { continue } // skip near-constant categories
                let z = (Double(truncating: current as NSDecimalNumber) - mean) / stddev
                if z > 1.5, strongestAnomaly == nil || z > strongestAnomaly!.z {
                    strongestAnomaly = (slug, current, Decimal(mean), z)
                }
            }
            if let a = strongestAnomaly {
                let cat = CategoryEntity.find(slug: a.slug)
                out.append(SmartInsight(
                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: cat.color,
                    headline: "\(cat.name) spiked this month",
                    detail: "Spending is \(formatINR(a.current)) vs average \(formatINR(a.mean)). About \(Int(a.z.rounded()))σ above normal.",
                    actionLabel: nil
                ))
            }
        }

        // 6. Recurring transaction discovery — same merchant + similar amount
        //    appearing in 2+ prior months but not categorised as subscription/EMI.
        if !historicalTransactions.isEmpty {
            let recurring = findUnflaggedRecurring(in: historicalTransactions + expenses)
            if let top = recurring.first {
                out.append(SmartInsight(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: Color(hex: "#8B5CF6"),
                    headline: "\(top.merchant) looks recurring",
                    detail: "Charged about \(formatINR(top.amount)) every month. Tag it as Subscription or EMI for cleaner totals.",
                    actionLabel: nil
                ))
            }
        }

        // 7. Goal-acceleration suggestion — if a goal is short, name the wants
        //    category that could be cut to cover the shortfall. Reuses
        //    `monthlyDisposable` computed earlier in section 3.
        for goal in goals.prefix(1) where !goal.isCompleted {
            guard let needed = goal.monthlyRequired, needed > monthlyDisposable else { continue }
            let shortfall = needed - monthlyDisposable
            // Find the biggest "want" category to suggest as the funding source.
            let wantsByCat = Dictionary(grouping: expenses.filter {
                CategoryEntity.find(slug: $0.categorySlug).intent == .want
            }, by: { $0.categorySlug })
                .mapValues { $0.reduce(Decimal(0)) { $0 + $1.amount } }
            if let top = wantsByCat.max(by: { $0.value < $1.value }), top.value >= shortfall {
                let cat = CategoryEntity.find(slug: top.key)
                let cutPct = Int((Double(truncating: (shortfall / top.value * 100) as NSDecimalNumber)).rounded())
                out.append(SmartInsight(
                    icon: "target",
                    iconColor: goal.type.color,
                    headline: "Cut \(cat.name) \(cutPct)% to hit \(goal.name)",
                    detail: "Reducing \(cat.name) (now \(formatINR(top.value))) by \(formatINR(shortfall))/mo would close the gap.",
                    actionLabel: nil
                ))
            }
        }

        return out
    }

    /// Find merchants with ≥3 occurrences across distinct months at roughly the
    /// same amount (within 15%), that AREN'T already in the subscriptions/EMI
    /// category. Result sorted by total amount descending.
    private static func findUnflaggedRecurring(in transactions: [TransactionEntity]) -> [(merchant: String, amount: Decimal)] {
        let cal = Calendar.current
        let candidates = transactions.filter {
            $0.isDebit && $0.categorySlug != "subscriptions" && $0.categorySlug != "emi"
        }
        let byMerchant = Dictionary(grouping: candidates) { txn -> String in
            (txn.merchantName.isEmpty ? txn.merchantRaw : txn.merchantName).lowercased()
        }
        var results: [(String, Decimal)] = []
        for (key, txns) in byMerchant where txns.count >= 3 {
            let monthsHit = Set(txns.map { cal.dateComponents([.year, .month], from: $0.date) }).count
            guard monthsHit >= 3 else { continue }
            // Amount tightly clustered?
            let amounts = txns.map { Double(truncating: $0.amount as NSDecimalNumber) }
            let avg = amounts.reduce(0, +) / Double(amounts.count)
            let withinBand = amounts.allSatisfy { abs($0 - avg) / avg < 0.15 }
            guard withinBand else { continue }
            let displayName = txns.first.map { $0.merchantName.isEmpty ? $0.merchantRaw : $0.merchantName } ?? key
            results.append((displayName, Decimal(avg)))
        }
        return results.sorted { $0.1 > $1.1 }
    }

    private static func formatINR(_ amount: Decimal) -> String {
        let d = Double(truncating: amount as NSDecimalNumber)
        if d >= 1_00_000 { return String(format: "₹%.1fL", d / 1_00_000) }
        if d >= 1_000    { return String(format: "₹%.0fK", d / 1_000) }
        return String(format: "₹%.0f", d)
    }
}
