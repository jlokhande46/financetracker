import SwiftUI

/// CRUD sheet for investment holdings — the user adds/edits their MF,
/// stocks, FDs, gold, PPF, etc. with current value + invested amount.
/// Opened from the Net Worth card on Analytics.
struct ManageInvestmentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container
    @State private var holdings: [InvestmentHoldingEntity] = []
    @State private var showAdd = false
    @State private var editing: InvestmentHoldingEntity? = nil
    @AppStorage("hideAmounts") private var hideAmounts: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                if holdings.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Investments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgPrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.brandPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.brandPrimary)
                    }
                }
            }
            .onAppear { reload() }
            .sheet(isPresented: $showAdd) {
                AddEditInvestmentSheet(existing: nil) { saved in
                    container?.investmentRepo.save(saved)
                    reload()
                }
            }
            .sheet(item: $editing) { holding in
                AddEditInvestmentSheet(existing: holding) { saved in
                    container?.investmentRepo.save(saved)
                    reload()
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: Spacing.sm) {
                summaryHeader
                ForEach(holdings) { h in
                    holdingRow(h)
                }
            }
            .padding(Spacing.base)
        }
    }

    private var summaryHeader: some View {
        let total = holdings.reduce(Decimal(0)) { $0 + $1.currentValue }
        let invested = holdings.reduce(Decimal(0)) { $0 + $1.investedAmount }
        let returns = total - invested
        return HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Current Value")
                    .font(.micro)
                    .foregroundStyle(Color.textSecondary)
                Text(total.currencyString(hidden: hideAmounts))
                    .font(.amount(20, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Returns")
                    .font(.micro)
                    .foregroundStyle(Color.textSecondary)
                let sign = returns >= 0 ? "+" : ""
                Text(hideAmounts ? hiddenAmountPlaceholder : "\(sign)\(returns.compactString)")
                    .font(.amount(16, weight: .semibold))
                    .foregroundStyle(returns >= 0 ? Color.incomeGreen : Color.expenseRed)
            }
        }
        .padding(Spacing.base)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func holdingRow(_ h: InvestmentHoldingEntity) -> some View {
        Button { editing = h } label: {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(h.type.color.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: h.type.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(h.type.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(h.name)
                        .font(.bodyMedium)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(h.type.displayName)
                            .font(.micro)
                            .foregroundStyle(Color.textTertiary)
                        Text("· updated \(h.lastUpdated.dayMonthYear)")
                            .font(.micro)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(h.currentValue.currencyString(hidden: hideAmounts))
                        .font(.amount(14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    if h.investedAmount > 0 && !hideAmounts {
                        let pct = h.returnsPct
                        Text(String(format: "%+.1f%%", pct))
                            .font(.micro)
                            .foregroundStyle(pct >= 0 ? Color.incomeGreen : Color.expenseRed)
                    }
                }
            }
            .padding(Spacing.base)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                container?.investmentRepo.delete(h.id)
                reload()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text("No investments tracked")
                .font(.titleLarge)
                .foregroundStyle(Color.textPrimary)
            Text("Add your mutual funds, stocks, FDs, gold, etc.\nUpdate values monthly for net-worth trends.")
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button { showAdd = true } label: {
                Text("Add First Holding")
                    .font(.titleMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.md)
                    .background(Color.brandPrimary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(Spacing.xl)
    }

    private func reload() {
        holdings = container?.investmentRepo.fetchAll() ?? []
    }
}

// MARK: - Add/Edit sheet

private struct AddEditInvestmentSheet: View {
    let existing: InvestmentHoldingEntity?
    let onSave: (InvestmentHoldingEntity) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var type: InvestmentType
    @State private var currentValueStr: String
    @State private var investedStr: String
    @State private var notes: String

    init(existing: InvestmentHoldingEntity?, onSave: @escaping (InvestmentHoldingEntity) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _type = State(initialValue: existing?.type ?? .mutualFund)
        _currentValueStr = State(initialValue: existing.map { "\($0.currentValue)" } ?? "")
        _investedStr = State(initialValue: existing.map { "\($0.investedAmount)" } ?? "")
        _notes = State(initialValue: existing?.notes ?? "")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        Decimal(string: currentValueStr) != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        field(title: "NAME", placeholder: "e.g. Parag Parikh Flexi Cap, HDFC FD", text: $name)

                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("TYPE")
                                .font(.micro)
                                .foregroundStyle(Color.textSecondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Spacing.sm) {
                                    ForEach(InvestmentType.allCases) { t in
                                        Button {
                                            withAnimation(.springy) { type = t }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: t.icon)
                                                    .font(.system(size: 12))
                                                Text(t.displayName)
                                                    .font(.caption)
                                            }
                                            .foregroundStyle(type == t ? .white : Color.textSecondary)
                                            .padding(.horizontal, Spacing.md)
                                            .padding(.vertical, Spacing.sm)
                                            .background(type == t ? t.color : Color.bgCard)
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        amountField(title: "CURRENT VALUE", placeholder: "Today's value", text: $currentValueStr)
                        amountField(title: "INVESTED AMOUNT", placeholder: "Total cost basis (optional)", text: $investedStr)
                        field(title: "NOTES", placeholder: "Optional", text: $notes)
                    }
                    .padding(Spacing.base)
                }
            }
            .navigationTitle(existing == nil ? "Add Holding" : "Edit Holding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(canSave ? Color.brandPrimary : Color.textTertiary)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func field(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(.micro).foregroundStyle(Color.textSecondary)
            TextField(placeholder, text: text)
                .font(.bodyMedium).foregroundStyle(Color.textPrimary).tint(Color.brandPrimary)
                .padding(Spacing.base).background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    private func amountField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(.micro).foregroundStyle(Color.textSecondary)
            HStack(spacing: 4) {
                Text("₹").font(.amount(16)).foregroundStyle(Color.textSecondary)
                TextField(placeholder, text: text)
                    .font(.amount(16)).foregroundStyle(Color.textPrimary)
                    .keyboardType(.decimalPad).tint(Color.brandPrimary)
            }
            .padding(Spacing.base).background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    private func save() {
        let entity = InvestmentHoldingEntity(
            id: existing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            currentValue: Decimal(string: currentValueStr) ?? 0,
            investedAmount: Decimal(string: investedStr) ?? 0,
            lastUpdated: Date(),
            notes: notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes,
            createdAt: existing?.createdAt ?? Date()
        )
        onSave(entity)
        dismiss()
    }
}
