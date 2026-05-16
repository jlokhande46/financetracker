import Foundation
import SwiftData

@Model
final class TransactionModel {
    @Attribute(.unique) var id: UUID
    var amount: Double
    var typeRaw: String
    var merchantRaw: String
    var merchantName: String
    var categorySlug: String
    var subcategorySlug: String?
    var date: Date
    var sourceRaw: String
    var confidence: Double
    var isConfirmed: Bool
    var isRecurring: Bool
    var isSplit: Bool
    var parentId: UUID?
    var tags: [String]
    var notes: String?
    var accountId: UUID?
    var receiptURL: String?
    var upiRef: String?
    var bankRef: String?
    var rawContent: String?
    var isHidden: Bool
    var isDeleted: Bool
    /// Optional per-transaction intent override ("need" | "want" | "saving").
    /// When nil, the category's default intent applies. SwiftData auto-migrates
    /// existing records to nil for this new field.
    var intentOverrideRaw: String?
    var createdAt: Date
    var updatedAt: Date

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .debit }
        set { typeRaw = newValue.rawValue }
    }

    var source: TransactionSource {
        get { TransactionSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        amount: Double,
        typeRaw: String,
        merchantRaw: String = "",
        merchantName: String = "",
        categorySlug: String = "others",
        subcategorySlug: String? = nil,
        date: Date = Date(),
        sourceRaw: String = "manual",
        confidence: Double = 1.0,
        isConfirmed: Bool = false,
        isRecurring: Bool = false,
        isSplit: Bool = false,
        parentId: UUID? = nil,
        tags: [String] = [],
        notes: String? = nil,
        accountId: UUID? = nil,
        receiptURL: String? = nil,
        upiRef: String? = nil,
        bankRef: String? = nil,
        rawContent: String? = nil,
        isHidden: Bool = false,
        isDeleted: Bool = false,
        intentOverrideRaw: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.amount = amount
        self.typeRaw = typeRaw
        self.merchantRaw = merchantRaw
        self.merchantName = merchantName
        self.categorySlug = categorySlug
        self.subcategorySlug = subcategorySlug
        self.date = date
        self.sourceRaw = sourceRaw
        self.confidence = confidence
        self.isConfirmed = isConfirmed
        self.isRecurring = isRecurring
        self.isSplit = isSplit
        self.parentId = parentId
        self.tags = tags
        self.notes = notes
        self.accountId = accountId
        self.receiptURL = receiptURL
        self.upiRef = upiRef
        self.bankRef = bankRef
        self.rawContent = rawContent
        self.isHidden = isHidden
        self.isDeleted = isDeleted
        self.intentOverrideRaw = intentOverrideRaw
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    func toEntity() -> TransactionEntity {
        TransactionEntity(
            id: id,
            amount: Decimal(amount),
            type: type,
            merchantRaw: merchantRaw,
            merchantName: merchantName,
            categorySlug: categorySlug,
            subcategorySlug: subcategorySlug,
            date: date,
            source: source,
            confidence: confidence,
            isConfirmed: isConfirmed,
            isRecurring: isRecurring,
            isSplit: isSplit,
            parentId: parentId,
            tags: tags,
            notes: notes,
            accountId: accountId,
            receiptURL: receiptURL,
            upiRef: upiRef,
            bankRef: bankRef,
            rawContent: rawContent,
            intentOverride: intentOverrideRaw.flatMap { CategoryIntent(rawValue: $0) },
            createdAt: createdAt
        )
    }

    static func from(entity: TransactionEntity) -> TransactionModel {
        TransactionModel(
            id: entity.id,
            amount: Double(truncating: entity.amount as NSDecimalNumber),
            typeRaw: entity.type.rawValue,
            merchantRaw: entity.merchantRaw,
            merchantName: entity.merchantName,
            categorySlug: entity.categorySlug,
            subcategorySlug: entity.subcategorySlug,
            date: entity.date,
            sourceRaw: entity.source.rawValue,
            confidence: entity.confidence,
            isConfirmed: entity.isConfirmed,
            isRecurring: entity.isRecurring,
            isSplit: entity.isSplit,
            parentId: entity.parentId,
            tags: entity.tags,
            notes: entity.notes,
            accountId: entity.accountId,
            receiptURL: entity.receiptURL,
            upiRef: entity.upiRef,
            bankRef: entity.bankRef,
            rawContent: entity.rawContent,
            intentOverrideRaw: entity.intentOverride?.rawValue,
            createdAt: entity.createdAt
        )
    }
}
