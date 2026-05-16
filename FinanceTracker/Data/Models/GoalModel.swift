import Foundation
import SwiftData

@Model
final class GoalModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var typeRaw: String
    var targetAmountDouble: Double
    var currentAmountDouble: Double
    var targetDate: Date?
    var notes: String?
    var isCompleted: Bool
    var createdAt: Date

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
