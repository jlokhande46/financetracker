import Foundation
import SwiftData

/// User-defined merchant → category mapping.
/// Persisted so the app remembers past corrections and auto-applies them.
@Model
final class MerchantRuleModel {
    @Attribute(.unique) var id: UUID = UUID()
    /// Normalized lowercased merchant key for matching (substring match)
    var merchantKey: String = ""
    /// Display version of the merchant name
    var merchantDisplay: String = ""
    var categorySlug: String = "others"
    var matchCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        merchantKey: String,
        merchantDisplay: String,
        categorySlug: String,
        matchCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.merchantKey = merchantKey
        self.merchantDisplay = merchantDisplay
        self.categorySlug = categorySlug
        self.matchCount = matchCount
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
