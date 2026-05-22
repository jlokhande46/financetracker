import Foundation
import SwiftData

/// SwiftData mirror of `RecurringBillEntity`. All non-id properties have
/// property-level defaults so SwiftData auto-migrates older installs that
/// pre-date this table.
@Model
final class RecurringBillModel {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var typeRaw: String = "other"
    /// Optional expected amount — `nil` for varying-amount bills like
    /// electricity. Stored as Double per the established Double-at-the-
    /// SwiftData-boundary convention.
    var amountDouble: Double?
    var frequencyRaw: String = "monthly"
    var dueDay: Int = 1
    var isActive: Bool = true
    var lastPaidCycleStart: Date?
    var lastPaidDate: Date?
    var lastPaidTransactionId: UUID?
    var notes: String?
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        typeRaw: String,
        amountDouble: Double? = nil,
        frequencyRaw: String = "monthly",
        dueDay: Int,
        isActive: Bool = true,
        lastPaidCycleStart: Date? = nil,
        lastPaidDate: Date? = nil,
        lastPaidTransactionId: UUID? = nil,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.typeRaw = typeRaw
        self.amountDouble = amountDouble
        self.frequencyRaw = frequencyRaw
        self.dueDay = dueDay
        self.isActive = isActive
        self.lastPaidCycleStart = lastPaidCycleStart
        self.lastPaidDate = lastPaidDate
        self.lastPaidTransactionId = lastPaidTransactionId
        self.notes = notes
        self.createdAt = createdAt
    }

    func toEntity() -> RecurringBillEntity {
        RecurringBillEntity(
            id: id,
            name: name,
            type: RecurringBillType(rawValue: typeRaw) ?? .other,
            amount: amountDouble.map { Decimal($0) },
            frequency: RecurringBillFrequency(rawValue: frequencyRaw) ?? .monthly,
            dueDay: dueDay,
            isActive: isActive,
            lastPaidCycleStart: lastPaidCycleStart,
            lastPaidDate: lastPaidDate,
            lastPaidTransactionId: lastPaidTransactionId,
            notes: notes,
            createdAt: createdAt
        )
    }
}
