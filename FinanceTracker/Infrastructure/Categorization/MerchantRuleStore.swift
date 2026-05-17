import Foundation
import SwiftData

/// Global store for user-defined merchant categorization rules.
/// Singleton because SMSParser / classifier code paths need to consult it
/// from many places, but it's bound to a ModelContext at app launch.
@MainActor
final class MerchantRuleStore {
    static let shared = MerchantRuleStore()

    private var modelContext: ModelContext?

    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Lookup

    /// Best-matching rule (most specific) for a given raw merchant string.
    private func bestRule(for merchant: String) -> MerchantRuleModel? {
        guard let context = modelContext else { return nil }
        let key = normalize(merchant)
        guard !key.isEmpty else { return nil }

        let descriptor = FetchDescriptor<MerchantRuleModel>()
        guard let rules = try? context.fetch(descriptor) else { return nil }
        let matches = rules.filter { rule in
            !rule.merchantKey.isEmpty && (key.contains(rule.merchantKey) || rule.merchantKey.contains(key))
        }
        return matches.max { $0.merchantKey.count < $1.merchantKey.count }
    }

    /// Returns category slug if a saved user rule matches this merchant.
    func categoryForMerchant(_ merchant: String) -> String? {
        guard let rule = bestRule(for: merchant) else { return nil }
        rule.matchCount += 1
        rule.updatedAt = Date()
        try? modelContext?.save()
        return rule.categorySlug
    }

    /// Returns the user's preferred display name if a saved rule matches this merchant.
    /// Use this when normalizing — it overrides alias-map / heuristic cleaning.
    func displayNameForMerchant(_ merchant: String) -> String? {
        guard let rule = bestRule(for: merchant) else { return nil }
        let display = rule.merchantDisplay.trimmingCharacters(in: .whitespaces)
        // Only return the saved display if the user actually customized it (not the
        // same as the raw merchant — otherwise we'd block normal alias-map behaviour).
        guard !display.isEmpty, display.lowercased() != merchant.lowercased() else { return nil }
        return display
    }

    // MARK: - Save / update

    /// Save a rule. Either `categorySlug` or `displayName` (or both) may be provided.
    /// If a rule already exists for this normalized merchant key, the supplied fields
    /// are updated and the others left alone — so saving just a name doesn't clobber
    /// a previously-saved category, and vice versa.
    func saveRule(merchant: String, categorySlug: String? = nil, displayName: String? = nil) {
        guard let context = modelContext else { return }
        let key = normalize(merchant)
        guard !key.isEmpty else { return }

        let descriptor = FetchDescriptor<MerchantRuleModel>(
            predicate: #Predicate { $0.merchantKey == key }
        )
        if let existing = try? context.fetch(descriptor).first {
            if let categorySlug { existing.categorySlug = categorySlug }
            if let displayName, !displayName.isEmpty { existing.merchantDisplay = displayName }
            existing.matchCount += 1
            existing.updatedAt = Date()
        } else {
            let rule = MerchantRuleModel(
                merchantKey: key,
                merchantDisplay: (displayName?.isEmpty == false ? displayName! : merchant),
                categorySlug: categorySlug ?? "others"
            )
            context.insert(rule)
        }
        try? context.save()
    }

    func deleteRule(id: UUID) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<MerchantRuleModel>(
            predicate: #Predicate { $0.id == id }
        )
        if let rule = try? context.fetch(descriptor).first {
            context.delete(rule)
            try? context.save()
        }
    }

    func fetchAllRules() -> [(id: UUID, merchant: String, categorySlug: String, matchCount: Int)] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<MerchantRuleModel>(
            sortBy: [SortDescriptor(\.matchCount, order: .reverse)]
        )
        guard let rules = try? context.fetch(descriptor) else { return [] }
        return rules.map { ($0.id, $0.merchantDisplay, $0.categorySlug, $0.matchCount) }
    }

    func deleteAll() {
        guard let context = modelContext else { return }
        guard let rules = try? context.fetch(FetchDescriptor<MerchantRuleModel>()) else { return }
        for rule in rules { context.delete(rule) }
        try? context.save()
    }

    // MARK: - Helpers

    private func normalize(_ raw: String) -> String {
        var s = raw.lowercased()
        // Strip UPI / POS / NEFT prefixes so "upi-swiggy" and "swiggy" share a key.
        s = s.replacingOccurrences(of: #"^(?:upi[-/ ]|pos[-/ ]|neft[-/ ]|imps[-/ ]|rtgs[-/ ]|pay[-*]|cas[-*])"#,
                                   with: "", options: .regularExpression)
        // Strip everything after "@" (UPI VPA handle: "jay@okhdfc" → "jay").
        if let at = s.firstIndex(of: "@") {
            s = String(s[..<at])
        }
        s = s.replacingOccurrences(of: #"[^a-z0-9 ]"#, with: " ", options: .regularExpression)
        // Drop long digit runs (UPI/ref numbers) so the key isn't transaction-specific.
        s = s.replacingOccurrences(of: #"\b\d{5,}\b"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }
}
