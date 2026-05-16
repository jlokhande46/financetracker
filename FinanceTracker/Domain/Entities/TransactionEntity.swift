import Foundation

struct TransactionEntity: Identifiable, Equatable {
    let id: UUID
    var amount: Decimal
    var type: TransactionType
    var merchantRaw: String
    var merchantName: String
    var categorySlug: String
    var subcategorySlug: String?
    var date: Date
    var source: TransactionSource
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
    var intentOverride: CategoryIntent?
    var createdAt: Date

    var isDebit: Bool { type == .debit }
    var isCredit: Bool { type == .credit }
    var needsReview: Bool { !isConfirmed && confidence < 0.85 }

    /// Intent for the 50/30/20 breakdown. User-set override takes precedence
    /// over the category's default mapping.
    var effectiveIntent: CategoryIntent? {
        if let override = intentOverride { return override }
        return CategoryEntity.find(slug: categorySlug).intent
    }

    init(
        id: UUID = UUID(),
        amount: Decimal,
        type: TransactionType,
        merchantRaw: String = "",
        merchantName: String = "",
        categorySlug: String = "others",
        subcategorySlug: String? = nil,
        date: Date = Date(),
        source: TransactionSource = .manual,
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
        intentOverride: CategoryIntent? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.amount = amount
        self.type = type
        self.merchantRaw = merchantRaw
        self.merchantName = merchantName
        self.categorySlug = categorySlug
        self.subcategorySlug = subcategorySlug
        self.date = date
        self.source = source
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
        self.intentOverride = intentOverride
        self.createdAt = createdAt
    }
}

enum TransactionType: String, Codable, CaseIterable {
    case debit  = "debit"
    case credit = "credit"
}

enum TransactionSource: String, Codable, CaseIterable {
    case sms     = "sms"
    case email   = "email"
    case pdf     = "pdf"
    case aa      = "aa"
    case manual  = "manual"
    case upi     = "upi"

    var displayName: String {
        switch self {
        case .sms:    return "SMS"
        case .email:  return "Email"
        case .pdf:    return "Statement"
        case .aa:     return "Bank Sync"
        case .manual: return "Manual"
        case .upi:    return "UPI"
        }
    }
}
