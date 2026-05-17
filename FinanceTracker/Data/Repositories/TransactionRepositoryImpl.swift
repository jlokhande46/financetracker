import Foundation
import SwiftData

@MainActor
class TransactionRepositoryImpl {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll(from startDate: Date? = nil, to endDate: Date? = nil) -> [TransactionEntity] {
        var descriptor = FetchDescriptor<TransactionModel>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        // #Predicate doesn't support dynamic composition, so branch explicitly.
        if let start = startDate, let end = endDate {
            descriptor.predicate = #Predicate<TransactionModel> { m in
                !m.isDeleted && !m.isHidden && m.date >= start && m.date <= end
            }
        } else if let start = startDate {
            descriptor.predicate = #Predicate<TransactionModel> { m in
                !m.isDeleted && !m.isHidden && m.date >= start
            }
        } else if let end = endDate {
            descriptor.predicate = #Predicate<TransactionModel> { m in
                !m.isDeleted && !m.isHidden && m.date <= end
            }
        } else {
            descriptor.predicate = #Predicate<TransactionModel> { m in
                !m.isDeleted && !m.isHidden
            }
        }
        do {
            let models = try modelContext.fetch(descriptor)
            return models.map { $0.toEntity() }
        } catch {
            assertionFailure("Failed to fetch transactions: \(error)")
            return []
        }
    }

    func fetchForMonth(_ date: Date) -> [TransactionEntity] {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let start = calendar.date(from: comps),
              let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start)
        else { return [] }
        return fetchAll(from: start, to: end)
    }

    func fetchPendingReview() -> [TransactionEntity] {
        let descriptor = FetchDescriptor<TransactionModel>(
            predicate: #Predicate { !$0.isConfirmed && $0.confidence < 0.85 && !$0.isDeleted },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor))?.map { $0.toEntity() } ?? []
    }

    func save(_ entity: TransactionEntity) {
        let model = TransactionModel.from(entity: entity)
        modelContext.insert(model)
        persistChanges()
    }

    func update(_ entity: TransactionEntity) {
        let id = entity.id
        let descriptor = FetchDescriptor<TransactionModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = (try? modelContext.fetch(descriptor))?.first else { return }
        model.amount = NSDecimalNumber(decimal: entity.amount).doubleValue
        model.typeRaw = entity.type.rawValue
        model.merchantRaw = entity.merchantRaw
        model.merchantName = entity.merchantName
        model.categorySlug = entity.categorySlug
        model.subcategorySlug = entity.subcategorySlug
        model.date = entity.date
        model.sourceRaw = entity.source.rawValue
        model.confidence = entity.confidence
        model.isConfirmed = entity.isConfirmed
        model.isRecurring = entity.isRecurring
        model.isSplit = entity.isSplit
        model.parentId = entity.parentId
        model.tags = entity.tags
        model.notes = entity.notes
        model.receiptURL = entity.receiptURL
        model.upiRef = entity.upiRef
        model.bankRef = entity.bankRef
        model.updatedAt = Date()
        persistChanges()
    }

    func delete(id: UUID) {
        let descriptor = FetchDescriptor<TransactionModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = (try? modelContext.fetch(descriptor))?.first else { return }
        model.isDeleted = true
        persistChanges()
    }

    func saveBulk(_ entities: [TransactionEntity]) {
        for entity in entities {
            modelContext.insert(TransactionModel.from(entity: entity))
        }
        persistChanges()
    }

    func deleteAll() {
        guard let models = try? modelContext.fetch(FetchDescriptor<TransactionModel>()) else { return }
        for model in models { modelContext.delete(model) }
        persistChanges()
    }

    /// Scan every transaction with `accountId == nil` and try to link it to an
    /// account by inspecting its `rawContent`. Uses the same bank/last4 hints
    /// the new SMS auto-linker does. Returns the number of rows that got linked.
    @discardableResult
    func relinkOrphanTransactions(accounts: [AccountEntity]) -> Int {
        let descriptor = FetchDescriptor<TransactionModel>(
            predicate: #Predicate<TransactionModel> { $0.accountId == nil && !$0.isDeleted }
        )
        guard let orphans = try? modelContext.fetch(descriptor) else { return 0 }

        let bankToLast4: [(needle: String, last4: String)] = [
            ("federal bank", "8708"), ("federalbank", "8708"),
        ]
        let bankNeedles: [(needle: String, bankSubstring: String)] = [
            ("federal bank", "federal"), ("hdfc bank", "hdfc"),
            ("icici bank",   "icici"),   ("sbi",       "sbi"),
            ("axis bank",    "axis"),
        ]

        var linked = 0
        for model in orphans {
            let raw = (model.rawContent ?? "").lowercased()
            guard !raw.isEmpty else { continue }
            // 1. Direct last4 mention "*6624" / "card 6624"
            var matchedID: UUID? = nil
            for acc in accounts where acc.last4 != nil {
                let l4 = acc.last4!
                if raw.contains("*\(l4)") || raw.contains("ending \(l4)") ||
                   raw.contains("xx\(l4)") || raw.contains(" \(l4) ") ||
                   raw.contains(" \(l4).") {
                    matchedID = acc.id
                    break
                }
            }
            // 2. Bank keyword → known last4
            if matchedID == nil {
                for hint in bankToLast4 where raw.contains(hint.needle) {
                    if let acc = accounts.first(where: { $0.last4 == hint.last4 }) {
                        matchedID = acc.id
                        break
                    }
                }
            }
            // 3. Bank keyword → single account from that bank
            if matchedID == nil {
                for hint in bankNeedles where raw.contains(hint.needle) {
                    let candidates = accounts.filter { $0.bankName.lowercased().contains(hint.bankSubstring) }
                    if candidates.count == 1 { matchedID = candidates.first?.id; break }
                }
            }

            if let id = matchedID {
                model.accountId = id
                model.updatedAt = Date()
                linked += 1
            }
        }
        if linked > 0 { persistChanges() }
        return linked
    }

    /// Re-categorizes all non-deleted transactions that match either `merchantRaw` or
    /// `merchantNameKey` and currently have a different category.
    /// Returns the number of records updated.
    @discardableResult
    func bulkRecategorize(merchantRaw merchantRawKey: String, merchantNameKey: String, newSlug: String) -> Int {
        let descriptor = FetchDescriptor<TransactionModel>(
            predicate: #Predicate<TransactionModel> { m in
                !m.isDeleted &&
                (m.merchantRaw == merchantRawKey || m.merchantName == merchantNameKey)
            }
        )
        guard let models = try? modelContext.fetch(descriptor) else { return 0 }
        let toUpdate = models.filter { $0.categorySlug != newSlug }
        for model in toUpdate {
            model.categorySlug = newSlug
            model.updatedAt = Date()
        }
        if !toUpdate.isEmpty { persistChanges() }
        return toUpdate.count
    }

    func seedSampleData() {
        let count = (try? modelContext.fetch(FetchDescriptor<TransactionModel>()).count) ?? 0
        guard count == 0 else { return }
        for entity in SampleData.transactions {
            modelContext.insert(TransactionModel.from(entity: entity))
        }
        persistChanges()
    }

    private func persistChanges() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("SwiftData save failed: \(error)")
        }
    }
}
