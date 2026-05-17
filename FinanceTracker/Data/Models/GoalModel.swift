import Foundation
import SwiftData

@Model
final class GoalModel {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var typeRaw: String = "other"
    var targetAmountDouble: Double = 0
    var currentAmountDouble: Double = 0
    var targetDate: Date?
    var notes: String?
    var isCompleted: Bool = false
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        typeRaw: String = "other",
        targetAmountDouble: Double,
        currentAmountDouble: Double = 0,
        targetDate: Date? = nil,
        notes: String? = nil,
        isCompleted: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.typeRaw = typeRaw
        self.targetAmountDouble = targetAmountDouble
        self.currentAmountDouble = currentAmountDouble
        self.targetDate = targetDate
        self.notes = notes
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }

    func toEntity() -> GoalEntity {
        GoalEntity(
            id: id,
            name: name,
            type: GoalType(rawValue: typeRaw) ?? .other,
            targetAmount: Decimal(targetAmountDouble),
            currentAmount: Decimal(currentAmountDouble),
            targetDate: targetDate,
            notes: notes,
            isCompleted: isCompleted,
            createdAt: createdAt
        )
    }
}
