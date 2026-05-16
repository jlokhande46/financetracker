import SwiftUI

struct AddGoalView: View {
    var existingGoal: GoalEntity? = nil
    var onSave: (GoalEntity) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedType: GoalType = .travel
    @State private var targetAmountString: String = ""
    @State private var currentAmountString: String = ""
    @State private var hasTargetDate: Bool = false
    @State private var targetDate: Date = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var notes: String = ""

    private var targetAmount: Decimal { Decimal(string: targetAmountString) ?? 0 }
    private var currentAmount: Decimal { Decimal(string: currentAmountString) ?? 0 }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && targetAmount > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {

                        // Type picker
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("GOAL TYPE")
                                .font(.micro)
                                .foregroundStyle(Color.textSecondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Spacing.sm) {
                                    ForEach(GoalType.allCases, id: \.self) { type in
                                        typeChip(type)
                                    }
                                }
                            }
                        }

                        // Name
                        labelled("NAME") {
                            TextField("e.g. Goa Trip", text: $name)
                                .font(.bodyMedium)
                                .foregroundStyle(Color.textPrimary)
                                .tint(Color.brandPrimary)
                                .padding(Spacing.base)
                                .background(Color.bgCard)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        }

                        // Target amount
                        labelled("TARGET AMOUNT") {
                            TextField("0", text: $targetAmountString)
                                .keyboardType(.decimalPad)
                                .font(.amount(22, weight: .bold))
                                .foregroundStyle(Color.textPrimary)
                                .padding(Spacing.base)
                                .background(Color.bgCard)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        }

                        // Already saved
                        labelled("ALREADY SAVED") {
                            TextField("0", text: $currentAmountString)
                                .keyboardType(.decimalPad)
                                .font(.bodyMedium)
                                .foregroundStyle(Color.textPrimary)
                                .padding(Spacing.base)
                                .background(Color.bgCard)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        }

                        // Target date
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack {
                                Text("TARGET DATE")
                                    .font(.micro)
                                    .foregroundStyle(Color.textSecondary)
                                Spacer()
                                Toggle("", isOn: $hasTargetDate)
                                    .tint(Color.brandPrimary)
                                    .labelsHidden()
                            }
                            if hasTargetDate {
                                DatePicker("", selection: $targetDate, in: Date()..., displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .colorScheme(.dark)
                                    .tint(Color.brandPrimary)
                                    .padding(.horizontal, Spacing.base)
                                    .padding(.vertical, Spacing.sm)
                                    .background(Color.bgCard)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                            }
                        }

                        // Notes
                        labelled("NOTES (OPTIONAL)") {
                            TextField("Add a note...", text: $notes, axis: .vertical)
                                .font(.bodyMedium)
                                .foregroundStyle(Color.textPrimary)
                                .tint(Color.brandPrimary)
                                .lineLimit(3...5)
                                .padding(Spacing.base)
                                .background(Color.bgCard)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        }

                        Button {
                            saveAndDismiss()
                        } label: {
                            Text(existingGoal == nil ? "Create Goal" : "Save Changes")
                                .font(.titleMedium)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.base)
                                .background(isValid ? selectedType.color : Color.bgElevated)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.full))
                                .animation(.springy, value: isValid)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isValid)
                        .padding(.top, Spacing.md)

                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, Spacing.base)
                    .padding(.top, Spacing.md)
                }
            }
            .navigationTitle(existingGoal == nil ? "New Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgPrimary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private func typeChip(_ type: GoalType) -> some View {
        Button {
            withAnimation(.springy) { selectedType = type }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: type.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(selectedType == type ? .white : type.color)
                Text(type.displayName)
                    .font(.micro)
                    .foregroundStyle(selectedType == type ? .white : Color.textSecondary)
            }
            .frame(width: 80, height: 64)
            .background(selectedType == type ? type.color : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    private func labelled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
            content()
        }
    }

    private func loadExisting() {
        guard let g = existingGoal else { return }
        name = g.name
        selectedType = g.type
        targetAmountString = "\(g.targetAmount)"
        currentAmountString = "\(g.currentAmount)"
        if let date = g.targetDate {
            hasTargetDate = true
            targetDate = date
        }
        notes = g.notes ?? ""
    }

    private func saveAndDismiss() {
        guard isValid else { return }
        let entity = GoalEntity(
            id: existingGoal?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            type: selectedType,
            targetAmount: targetAmount,
            currentAmount: currentAmount,
            targetDate: hasTargetDate ? targetDate : nil,
            notes: notes.isEmpty ? nil : notes,
            isCompleted: existingGoal?.isCompleted ?? false,
            createdAt: existingGoal?.createdAt ?? Date()
        )
        onSave(entity)
        dismiss()
    }
}
