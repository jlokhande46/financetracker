import Foundation

struct ClassificationResult {
    var categorySlug: String
    var confidence: Double
    var source: ClassificationSource
}

enum ClassificationSource {
    case exactRule, keywordMatch, mlModel, fallback
}

class CategoryClassifier {
    static let shared = CategoryClassifier()

    // Merchant → Category rules (ordered by specificity)
    private let merchantRules: [(merchant: String, slug: String)] = [
        // Food
        ("swiggy", "food"), ("zomato", "food"), ("blinkit", "food"),
        ("bigbasket", "food"), ("dunzo", "food"), ("dominos", "food"),
        ("mcdonalds", "food"), ("kfc", "food"), ("subway", "food"),
        ("starbucks", "food"), ("cafe", "food"), ("restaurant", "food"),
        ("pizza", "food"), ("biryani", "food"), ("dhaba", "food"),
        // Travel
        ("uber", "travel"), ("ola", "travel"), ("rapido", "travel"),
        ("irctc", "travel"), ("makemytrip", "travel"), ("goibibo", "travel"),
        ("metro", "travel"), ("dmrc", "travel"), ("bmtc", "travel"),
        ("yatra", "travel"), ("cleartrip", "travel"), ("redbus", "travel"),
        // Fuel
        ("bpcl", "fuel"), ("hpcl", "fuel"), ("indian oil", "fuel"),
        ("iocl", "fuel"), ("petrol", "fuel"), ("diesel", "fuel"),
        ("fuel", "fuel"), ("pump", "fuel"),
        // Entertainment
        ("netflix", "entertainment"), ("spotify", "entertainment"),
        ("hotstar", "entertainment"), ("amazon prime", "entertainment"),
        ("youtube premium", "entertainment"), ("zee5", "entertainment"),
        ("sonyliv", "entertainment"), ("voot", "entertainment"),
        ("pvr", "entertainment"), ("inox", "entertainment"),
        ("book my show", "entertainment"), ("bookmyshow", "entertainment"),
        // Shopping
        ("amazon", "shopping"), ("flipkart", "shopping"), ("myntra", "shopping"),
        ("meesho", "shopping"), ("nykaa", "shopping"), ("ajio", "shopping"),
        ("snapdeal", "shopping"), ("jiomart", "shopping"),
        // Bills
        ("electricity", "bills"), ("bescom", "bills"), ("tata power", "bills"),
        ("mahanagar gas", "bills"), ("igl gas", "bills"), ("bsnl", "bills"),
        ("airtel", "bills"), ("jio", "bills"), ("vodafone", "bills"),
        ("water", "bills"), ("internet", "bills"), ("broadband", "bills"),
        // Health
        ("apollo", "health"), ("medplus", "health"), ("pharmeasy", "health"),
        ("1mg", "health"), ("netmeds", "health"), ("hospital", "health"),
        ("clinic", "health"), ("pharmacy", "health"), ("doctor", "health"),
        // Subscriptions
        ("notion", "subscriptions"), ("dropbox", "subscriptions"),
        ("microsoft 365", "subscriptions"), ("adobe", "subscriptions"),
        ("github", "subscriptions"), ("slack", "subscriptions"),
        ("zoom", "subscriptions"), ("chatgpt", "subscriptions"),
        // Investments
        ("zerodha", "investments"), ("groww", "investments"),
        ("mutual fund", "investments"), ("sip", "investments"),
        ("equity", "investments"), ("nse", "investments"),
        // Salary/Income
        ("salary", "salary"), ("payroll", "salary"), ("neft", "salary"),
        // Transfers
        ("transfer", "transfer"), ("neft", "transfer"), ("rtgs", "transfer"),
        ("imps", "transfer"), ("phonepe", "transfer"), ("gpay", "transfer"),
        ("paytm", "transfer"), ("upi", "transfer"),
        // Rent
        ("rent", "rent"), ("nobroker", "rent"), ("magicbricks", "rent"),
        // EMI
        ("emi", "emi"), ("loan", "emi"), ("equated", "emi"),
    ]

    // Amount-based rules
    private func classifyByAmount(_ amount: Decimal, type: TransactionType) -> ClassificationResult? {
        if type == .credit {
            // Large regular credit = likely salary
            if amount >= 10000 {
                return ClassificationResult(categorySlug: "salary", confidence: 0.6, source: .keywordMatch)
            }
        }
        return nil
    }

    /// CC-payment narrations that should always classify as the "cc_payment" transfer.
    /// Kept here (not in keywordRules) because they need higher priority than amount
    /// heuristics and apply only to credits.
    private let ccPaymentMarkers: [String] = [
        "cc payment", "card payment", "bppy cc", "bppy/", "bppy ",
        "payment received", "payment thank you", "payment - thank you",
        "credit card payment", "bill payment received", "auto debit-cc payment"
    ]

    func classify(merchantName: String, amount: Decimal, type: TransactionType, rawContent: String? = nil) -> ClassificationResult {
        let lower = merchantName.lowercased()
        let rawLower = (rawContent ?? "").lowercased()

        // 0. CC-payment shortcut — runs BEFORE everything because a ₹26K CC payment
        // would otherwise hit the amount-based "salary" rule and look like income.
        if type == .credit,
           ccPaymentMarkers.contains(where: { lower.contains($0) || rawLower.contains($0) }) {
            return ClassificationResult(categorySlug: "cc_payment", confidence: 1.0, source: .keywordMatch)
        }

        // 1. User-defined rules win (learned from past corrections)
        if let userSlug = MainActor.assumeIsolated({
            MerchantRuleStore.shared.categoryForMerchant(merchantName)
        }) {
            return ClassificationResult(categorySlug: userSlug, confidence: 1.0, source: .exactRule)
        }

        // 2. Built-in keyword rules
        for rule in merchantRules {
            if lower.contains(rule.merchant) || rawLower.contains(rule.merchant) {
                return ClassificationResult(
                    categorySlug: rule.slug,
                    confidence: 0.92,
                    source: .keywordMatch
                )
            }
        }

        // Amount-based fallback
        if let amountResult = classifyByAmount(amount, type: type) {
            return amountResult
        }

        // Transfers detection
        if type == .credit && amount < 10000 {
            return ClassificationResult(categorySlug: "transfer", confidence: 0.55, source: .fallback)
        }

        return ClassificationResult(categorySlug: "others", confidence: 0.40, source: .fallback)
    }

    func applyUserRules(_ userRules: [UserCategorizationRule], to merchant: String) -> ClassificationResult? {
        for rule in userRules {
            switch rule.matchType {
            case .exact:
                if merchant.lowercased() == rule.pattern.lowercased() {
                    return ClassificationResult(categorySlug: rule.categorySlug, confidence: 1.0, source: .exactRule)
                }
            case .contains:
                if merchant.lowercased().contains(rule.pattern.lowercased()) {
                    return ClassificationResult(categorySlug: rule.categorySlug, confidence: 0.98, source: .exactRule)
                }
            }
        }
        return nil
    }
}

struct UserCategorizationRule {
    var pattern: String
    var matchType: RuleMatchType
    var categorySlug: String
}

enum RuleMatchType {
    case exact, contains
}
