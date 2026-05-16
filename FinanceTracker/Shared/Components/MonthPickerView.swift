import SwiftUI

// MARK: - MonthPickerView

struct MonthPickerView: View {

    @Binding var selectedMonth: Date
    @State private var showDatePicker: Bool = false
    @State private var slideDirection: SlideDirection = .forward

    private enum SlideDirection {
        case forward, backward
    }

    private var isCurrentMonth: Bool {
        let cal = Calendar.current
        let now = Date()
        return cal.isDate(selectedMonth, equalTo: now, toGranularity: .month)
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Left chevron — previous month
            Button {
                go(months: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.bgCard)
                    .clipShape(Circle())
            }

            Spacer()

            // Month label — tappable to open date picker
            Button {
                showDatePicker = true
            } label: {
                HStack(spacing: Spacing.xs) {
                    Text(monthYearString)
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)
                        .transition(
                            slideDirection == .forward
                                ? .asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                )
                                : .asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                )
                        )
                        .id(monthYearString)     // triggers transition on change

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()

            // Right chevron — next month (disabled if current month)
            Button {
                go(months: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isCurrentMonth ? .textSecondary.opacity(0.3) : .textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.bgCard)
                    .clipShape(Circle())
            }
            .disabled(isCurrentMonth)
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedMonth: $selectedMonth)
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Helpers

    private var monthYearString: String {
        selectedMonth.formatted(.dateTime.month(.wide).year())
    }

    private func go(months: Int) {
        slideDirection = months > 0 ? .forward : .backward
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            guard let newDate = Calendar.current.date(byAdding: .month, value: months, to: selectedMonth) else { return }
            selectedMonth = newDate
        }
    }
}

// MARK: - DatePickerSheet

private struct DatePickerSheet: View {

    @Binding var selectedMonth: Date
    @Environment(\.dismiss) private var dismiss
    @State private var pickerDate: Date

    init(selectedMonth: Binding<Date>) {
        self._selectedMonth = selectedMonth
        self._pickerDate = State(initialValue: selectedMonth.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgCard.ignoresSafeArea()

                DatePicker(
                    "Select Month",
                    selection: $pickerDate,
                    in: ...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .padding(.horizontal, Spacing.base)
            }
            .navigationTitle("Pick a Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        let cal = Calendar.current
                        let comps = cal.dateComponents([.year, .month], from: pickerDate)
                        if let startOfMonth = cal.date(from: comps) {
                            selectedMonth = startOfMonth
                        }
                        dismiss()
                    }
                    .font(.titleMedium)
                    .foregroundColor(.brandPrimary)
                }
            }
            .toolbarBackground(Color.bgCard, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.bgPrimary.ignoresSafeArea()
        MonthPickerView(selectedMonth: .constant(Date()))
            .padding()
    }
}
