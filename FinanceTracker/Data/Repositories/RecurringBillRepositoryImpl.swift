import Foundation
import SwiftData

@MainActor
final class RecurringBillRepositoryImpl {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() -> [RecurringBillEntity] {
        let descriptor = FetchDescriptor<RecurringBillModel>(
            sortBy: [SortDescriptor(\.dueDay)]
        )
        return (try? modelContext.fetch(descriptor))?.map { $0.toEntity() } ?? []
    }

    /// Bills that haven't been paid for the current cycle. Drives the
    /// "Bills Due" banner on the Dashboard and post-salary reminders.
    func fetchDueThisCycle() -> [RecurringBillEntity] {
        fetchAll().filter { $0.isDueThisCycle }
    }

    func save(_ entity: RecurringBillEntity) {
        // Upsert keyed by id.
        let existing = (try? modelContext.fetch(FetchDescriptor<RecurringBillModel>()))?
            .first { $0.id == entity.id }
        if let model = existing {
            model.name = entity.name
            model.typeRaw = entity.type.rawValue
            model.amountDouble = entity.amount.map { Double(truncating: $0 as NSDecimalNumber) }
            model.frequencyRaw = entity.frequency.rawValue
            model.dueDay = entity.dueDay
            model.isActive = entity.isActive
            model.lastPaidCycleStart = entity.lastPaidCycleStart
            model.lastPaidDate = entity.lastPaidDate
            model.lastPaidTransactionId = entity.lastPaidTransactionId
            model.notes = entity.notes
        } else {
            let model = RecurringBillModel(
                id: entity.id,
                name: entity.name,
                typeRaw: entity.type.rawValue,
                amountDouble: entity.amount.map { Double(truncating: $0 as NSDecimalNumber) },
                frequencyRaw: entity.frequency.rawValue,
                dueDay: entity.dueDay,
                isActive: entity.isActive,
                lastPaidCycleStart: entity.lastPaidCycleStart,
                lastPaidDate: entity.lastPaidDate,
                lastPaidTransactionId: entity.lastPaidTransactionId,
                notes: entity.notes,
                createdAt: entity.createdAt
            )
            modelContext.insert(model)
        }
        try? modelContext.save()
    }

    /// Marks the bill paid for its current cycle. Snapping `lastPaidCycleStart`
    /// to the entity's `currentCycleStart` (NOT just "now") guarantees the
    /// cycle math correctly considers this bill done for the period.
    /// `transactionId` is optional — user may pick "Paid outside app".
    func markPaid(billId: UUID, transactionId: UUID?, paidDate: Date = Date()) {
        guard let model = (try? modelContext.fetch(FetchDescriptor<RecurringBillModel>()))?
                .first(where: { $0.id == billId }) else { return }
        // Re-derive cycle start from the current state — the entity round-trip
        // recomputes it from dueDay + frequency.
        let entity = model.toEntity()
        model.lastPaidCycleStart = entity.currentCycleStart
        model.lastPaidDate = paidDate
        model.lastPaidTransactionId = transactionId
        try? modelContext.save()
    }

    /// Undo a paid-mark — clears the cycle stamp and any txn link.
    /// Used by the bills section's "Reset" context menu action.
    func resetLastPaid(billId: UUID) {
        guard let model = (try? modelContext.fetch(FetchDescriptor<RecurringBillModel>()))?
                .first(where: { $0.id == billId }) else { return }
        model.lastPaidCycleStart = nil
        model.lastPaidDate = nil
        model.lastPaidTransactionId = nil
        try? modelContext.save()
    }

    func delete(_ id: UUID) {
        guard let model = (try? modelContext.fetch(FetchDescriptor<RecurringBillModel>()))?
                .first(where: { $0.id == id }) else { return }
        modelContext.delete(model)
        try? modelContext.save()
    }

    func deleteAll() {
        guard let models = try? modelContext.fetch(FetchDescriptor<RecurringBillModel>()) else { return }
        for m in models { modelContext.delete(m) }
        try? modelContext.save()
    }

    /// On first launch, seed the five common Indian recurring bills the
    /// user mentioned so they don't start from an empty list. Each bill has
    /// a sensible default dueDay the user can edit. Skipped if any bill
    /// already exists (won't overwrite user data on re-runs).
    func seedDefaultsIfNeeded() {
        let count = (try? modelContext.fetch(FetchDescriptor<RecurringBillModel>()).count) ?? 0
        guard count == 0 else { return }
        let defaults: [RecurringBillEntity] = [
            RecurringBillEntity(name: "Rent",        type: .rent,        amount: 25_000, frequency: .monthly,   dueDay: 5),
            RecurringBillEntity(name: "Electricity", type: .electricity, amount: nil,    frequency: .monthly,   dueDay: 15),
            RecurringBillEntity(name: "Postpaid",    type: .postpaid,    amount: 800,    frequency: .monthly,   dueDay: 20),
            RecurringBillEntity(name: "Credit Card", type: .ccBill,      amount: nil,    frequency: .monthly,   dueDay: 30),
            RecurringBillEntity(name: "Gas",         type: .gas,         amount: 1_100,  frequency: .bimonthly, dueDay: 25),
        ]
        for bill in defaults { save(bill) }
    }
}
