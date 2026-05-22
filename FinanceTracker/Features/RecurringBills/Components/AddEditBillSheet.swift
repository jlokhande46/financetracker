import SwiftUI

/// Create / edit a recurring bill. Drives the BudgetsView "Add" button and
/// the BillCard tap (edit existing).
struct AddEditBillSheet: View {
    let existing: RecurringBillEntity?
    let onSave: (RecurringBillEntity) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var type: RecurringBillType
    @State private var amountString: String
    @State private var frequency: RecurringBillFrequency
    @State private var dueDay: Int
    @State private var notes: String
    @State private var isActive: Bool
    @FocusState private var amountFieldFocused: Bool

    init(existing: RecurringBillEntity? = nil, onSave: @escaping (RecurringBillEntity) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name      = State(initialValue: existing?.name ?? "")
        _type      = State(initialValue: existing?.type ?? .other)
        _amountString = State(initialValue: existing?.amount.map {
            "\($0)"
        } ?? "")
        _frequency = State(initialValue: existing?.frequency ?? .monthly)
        _dueDay    = State(initialValue: existing?.dueDay ?? 5)
        _notes     = State(initialValue: existing?.notes ?? "")
        _isActive  = State(initialValue: existing?.isActive ?? true)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var parsedAmount: Decimal? {
        let trimmed = amountString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        nameField
                        typeGrid
                        amountField
                        frequencyPicker
                        dueDayPicker
                        notesField
                        if existing != nil { activeToggle }
                    }
                    .padding(Spacing.base)
                    .padding(.bottom, Spacing.xxl)
                }
            }
            .navigationTitle(existing == nil ? "New Bill" : "Edit Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgPrimary, for: .navigationBar)
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

    // MARK: - Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("NAME")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
            TextField("e.g. Rent, Airtel Postpaid, Vi Gas", text: $name)
                .font(.bodyMedium)
                .foregroundStyle(Color.textPrimary)
                .tint(Color.brandPrimary)
                .padding(Spacing.base)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    private var typeGrid: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("TYPE")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: Spacing.sm)],
                      spacing: Spacing.sm) {
                ForEach(RecurringBillType.allCases) { t in
                    Button {
                        withAnimation(.springy) { type = t }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: t.icon)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(type == t ? .white : t.color)
                            Text(t.displayName)
                                .font(.micro)
                                .foregroundStyle(type == t ? .white : Color.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(type == t ? t.color : Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("EXPECTED AMOUNT")
                    .font(.micro)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("Optional")
                    .font(.micro)
                    .foregroundStyle(Color.textTertiary)
            }
            HStack(spacing: 4) {
                Text("₹")
                    .font(.amount(18))
                    .foregroundStyle(Color.textSecondary)
                TextField("Skip for varying amounts", text: $amountString)
                    .font(.amount(18))
                    .foregroundStyle(Color.textPrimary)
                    .keyboardType(.decimalPad)
                    .focused($amountFieldFocused)
                    .tint(Color.brandPrimary)
            }
            .padding(Spacing.base)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            Text("Used to pre-filter the picker when you mark this bill as paid.")
                .font(.micro)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var frequencyPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("FREQUENCY")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: 0) {
                ForEach(RecurringBillFrequency.allCases) { f in
                    Button {
                        withAnimation(.springy) { frequency = f }
                    } label: {
                        Text(f.displayName)
                            .font(.bodyMedium)
                            .foregroundStyle(frequency == f ? .white : Color.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                            .background(frequency == f ? Color.brandPrimary : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private var dueDayPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("DUE DAY")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
            HStack {
                Text("Day \(dueDay) of the month")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Stepper("", value: $dueDay, in: 1...31)
                    .labelsHidden()
            }
            .padding(Spacing.base)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            Text("In shorter months, the bill snaps to the last valid day (e.g. day 31 → Feb 28/29).")
                .font(.micro)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("NOTES")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
            TextField("Optional", text: $notes, axis: .vertical)
                .font(.bodyMedium)
                .foregroundStyle(Color.textPrimary)
                .tint(Color.brandPrimary)
                .lineLimit(2...4)
                .padding(Spacing.base)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    private var activeToggle: some View {
        Toggle("Active", isOn: $isActive)
            .tint(Color.brandPrimary)
            .padding(Spacing.base)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func save() {
        let entity = RecurringBillEntity(
            id: existing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            amount: parsedAmount,
            frequency: frequency,
            dueDay: dueDay,
            isActive: isActive,
            lastPaidCycleStart: existing?.lastPaidCycleStart,
            lastPaidDate: existing?.lastPaidDate,
            lastPaidTransactionId: existing?.lastPaidTransactionId,
            notes: notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes,
            createdAt: existing?.createdAt ?? Date()
        )
        onSave(entity)
        dismiss()
    }
}
