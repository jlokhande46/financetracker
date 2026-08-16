import SwiftUI

struct AccountDetailView: View {
    let account: AccountEntity

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container

    @State private var transactions: [TransactionEntity] = []
    @State private var statement: CardStatementEntity? = nil
    @State private var currentAccount: AccountEntity
    @State private var showEditCycle = false
    @State private var showEditOpeningBalance = false
    @State private var openingBalanceDraft: String = ""

    init(account: AccountEntity) {
        self.account = account
        self._currentAccount = State(initialValue: account)
    }

    private var formattedBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₹"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: currentAccount.balance as NSDecimalNumber) ?? "₹\(currentAccount.balance)"
    }

    private var formattedLimit: String? {
        guard let l = currentAccount.creditLimit else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₹"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: l as NSDecimalNumber)
    }

    private var thisMonthSpend: Decimal {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        let start = cal.date(from: comps) ?? Date()
        return transactions
            .filter { $0.isDebit && $0.date >= start }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        cardHero
                        statsRow
                        if let s = statement {
                            statementCard(s)
                        }
                        if account.type == .credit {
                            cycleCard
                        }
                        openingBalanceCard
                        recentTransactions
                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, Spacing.base)
                    .padding(.top, Spacing.base)
                }
            }
            .navigationTitle(account.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgPrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.brandPrimary)
                }
            }
            .task { load() }
            .alert("Opening Balance", isPresented: $showEditOpeningBalance) {
                TextField("Amount", text: $openingBalanceDraft)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    guard let value = Decimal(string: openingBalanceDraft.trimmingCharacters(in: .whitespaces)) else { return }
                    container?.accountRepo.updateOpeningBalance(id: account.id, openingBalance: value)
                    container?.refreshAccountBalances()
                    load()
                }
            } message: {
                Text(currentAccount.type == .credit
                     ? "Amount already outstanding on this card before the transactions FinanceTracker knows about."
                     : "Amount already in this account before the transactions FinanceTracker knows about.")
            }
            .sheet(isPresented: $showEditCycle) {
                EditCycleSheet(account: currentAccount, onSaved: { load() })
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    /// Balances are derived (opening balance +/- this account's transactions),
    /// so the opening figure has to be editable — otherwise a wrong starting
    /// point makes every downstream number permanently wrong.
    private var openingBalanceCard: some View {
        Button {
            openingBalanceDraft = "\(currentAccount.openingBalance)"
            showEditOpeningBalance = true
        } label: {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.incomeGreen.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.incomeGreen)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Opening Balance")
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                    Text(currentAccount.type == .credit
                         ? "Outstanding before tracked transactions"
                         : "Balance before tracked transactions")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Text(currentAccount.openingBalance.currencyString)
                    .font(.amount(14, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(Spacing.base)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var cycleCard: some View {
        Button {
            showEditCycle = true
        } label: {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.brandPrimary.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.brandPrimary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Billing Cycle")
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                    if let sd = currentAccount.statementDay, let dd = currentAccount.dueDay {
                        Text("Generates on \(ordinal(sd)) · Due on \(ordinal(dd))")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        Text("Tap to set statement & due dates for auto-reminders")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(Spacing.base)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
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

    private var cardHero: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: account.type.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                if let last4 = account.last4 {
                    Text("•••• \(last4)")
                        .font(.titleMedium)
                        .foregroundStyle(.white)
                        .monospaced()
                }
            }

            Spacer().frame(height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(currentAccount.type == .credit ? "Outstanding" : "Balance")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Text(formattedBalance)
                    .font(.amount(28, weight: .bold))
                    .foregroundStyle(.white)
            }

            if let limit = formattedLimit, let pct = currentAccount.utilizationPercent {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Limit \(limit)")
                            .font(.micro)
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text("\(Int(pct))% used")
                            .font(.micro)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.18))
                                .frame(height: 4)
                            Capsule()
                                .fill(Color.white)
                                .frame(width: geo.size.width * CGFloat(min(pct, 100) / 100), height: 4)
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(hex: account.colorHex), Color(hex: account.colorHex).opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
    }

    private var statsRow: some View {
        HStack(spacing: Spacing.md) {
            stat(label: "This month", value: compact(thisMonthSpend), color: Color.expenseRed)
            stat(label: "Bank", value: account.bankName, color: Color.brandPrimary)
            stat(label: "Type", value: account.type.displayName, color: Color.brandAccent)
        }
    }

    private func stat(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.bodyMedium)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.base)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    @ViewBuilder
    private func statementCard(_ s: CardStatementEntity) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("CURRENT STATEMENT")
                    .font(.micro)
                    .foregroundStyle(Color.textSecondary)
                    .kerning(1.2)
                Spacer()
                if s.isPaid {
                    Text("PAID")
                        .font(.micro)
                        .foregroundStyle(Color.incomeGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.incomeGreen.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("₹\(compact(s.totalDue))")
                    .font(.amount(24, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(s.isOverdue ? "Overdue by \(-s.daysUntilDue)d" : s.daysUntilDue == 0 ? "Due Today" : "Due in \(s.daysUntilDue)d")
                    .font(.caption)
                    .foregroundStyle(Color(hex: s.urgencyColor))
            }
        }
        .padding(Spacing.base)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("RECENT TRANSACTIONS")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
                .kerning(1.2)

            if transactions.isEmpty {
                Text("No transactions yet")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .padding(Spacing.base)
                    .frame(maxWidth: .infinity)
                    .background(Color.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            } else {
                VStack(spacing: 0) {
                    ForEach(transactions.prefix(15)) { txn in
                        miniRow(txn)
                        if txn.id != transactions.prefix(15).last?.id {
                            Divider().background(Color.textTertiary.opacity(0.15))
                                .padding(.horizontal, Spacing.base)
                        }
                    }
                }
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            }
        }
    }

    private func miniRow(_ txn: TransactionEntity) -> some View {
        HStack(spacing: Spacing.md) {
            CategoryIconView(slug: txn.categorySlug, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(txn.merchantName.isEmpty ? txn.merchantRaw : txn.merchantName)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(txn.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.micro)
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer()
            Text("\(txn.isCredit ? "+" : "-")₹\(compact(txn.amount))")
                .font(.amount(14))
                .foregroundStyle(txn.isCredit ? Color.incomeGreen : Color.textPrimary)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.sm)
    }

    private func load() {
        guard let container else { return }
        // Refresh in case cycle was just edited.
        if let updated = container.accountRepo.fetchAll().first(where: { $0.id == account.id }) {
            currentAccount = updated
        }
        transactions = container.transactionRepo.fetchAll()
            .filter { $0.accountId == account.id }
            .sorted { $0.date > $1.date }
        statement = container.cardStatementRepo.fetchAll()
            .first { $0.accountId == account.id && !$0.isPaid }
            ?? container.cardStatementRepo.fetchAll()
                .first { $0.accountId == account.id }
    }

    private func compact(_ amount: Decimal) -> String {
        let d = Double(truncating: amount as NSDecimalNumber)
        if d >= 1_00_00_000 { return String(format: "%.1fCr", d / 1_00_00_000) }
        if d >= 1_00_000    { return String(format: "%.1fL",  d / 1_00_000) }
        if d >= 1_000       { return String(format: "%.0fK",  d / 1_000) }
        return String(format: "%.0f", d)
    }
}
