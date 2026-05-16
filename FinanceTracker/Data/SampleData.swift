import Foundation

struct SampleData {
    static let accounts: [AccountEntity] = [
        AccountEntity(id: UUID(), name: "HDFC Savings", bankName: "HDFC Bank", type: .savings, last4: "6311", balance: 1_23_450, colorHex: "#3B82F6"),
        AccountEntity(id: UUID(), name: "HDFC Tata Neu Infinity", bankName: "HDFC Bank", type: .credit, last4: "6624", balance: 34_116, creditLimit: 5_00_000, colorHex: "#8B5CF6"),
        AccountEntity(id: UUID(), name: "HDFC Regalia Gold", bankName: "HDFC Bank", type: .credit, last4: "4493", balance: 3_237, creditLimit: 3_00_000, colorHex: "#6366F1"),
        AccountEntity(id: UUID(), name: "ICICI Sapphiro", bankName: "ICICI Bank", type: .credit, last4: "2000", balance: 0, creditLimit: 4_00_000, colorHex: "#F59E0B"),
        AccountEntity(id: UUID(), name: "SBI Cashback", bankName: "SBI", type: .credit, last4: "5075", balance: 27_354, creditLimit: 2_00_000, colorHex: "#10B981"),
        AccountEntity(id: UUID(), name: "Federal Bank Savings", bankName: "Federal Bank", type: .savings, last4: "8708", balance: 45_000, colorHex: "#06B6D4"),
    ]

    static var transactions: [TransactionEntity] {
        let cal = Calendar.current
        let now = Date()

        func daysAgo(_ n: Int) -> Date {
            cal.date(byAdding: .day, value: -n, to: now)!
        }

        return [
            // Today
            TransactionEntity(amount: 380, type: .debit, merchantRaw: "SWIGGY", merchantName: "Swiggy", categorySlug: "food", date: daysAgo(0), source: .upi, confidence: 0.95, isConfirmed: true),
            TransactionEntity(amount: 999, type: .debit, merchantRaw: "AMAZON", merchantName: "Amazon", categorySlug: "shopping", date: daysAgo(0), source: .sms, confidence: 0.92, isConfirmed: true),

            // Yesterday
            TransactionEntity(amount: 250, type: .debit, merchantRaw: "UBER", merchantName: "Uber", categorySlug: "travel", date: daysAgo(1), source: .upi, confidence: 0.97, isConfirmed: true),
            TransactionEntity(amount: 1_20_000, type: .credit, merchantRaw: "SALARY ACME CORP", merchantName: "Acme Corp Salary", categorySlug: "salary", date: daysAgo(1), source: .sms, confidence: 0.88, isConfirmed: true),
            TransactionEntity(amount: 149, type: .debit, merchantRaw: "NETFLIX.COM", merchantName: "Netflix", categorySlug: "subscriptions", date: daysAgo(1), source: .email, confidence: 0.99, isConfirmed: true, isRecurring: true),

            // 3 days ago
            TransactionEntity(amount: 2_500, type: .debit, merchantRaw: "BPCL FUEL", merchantName: "BPCL Fuel", categorySlug: "fuel", date: daysAgo(3), source: .sms, confidence: 0.94, isConfirmed: true),
            TransactionEntity(amount: 450, type: .debit, merchantRaw: "ZOMATO", merchantName: "Zomato", categorySlug: "food", date: daysAgo(3), source: .upi, confidence: 0.96, isConfirmed: true),

            // 5 days ago
            TransactionEntity(amount: 1_200, type: .debit, merchantRaw: "MYNTRA", merchantName: "Myntra", categorySlug: "shopping", date: daysAgo(5), source: .email, confidence: 0.91, isConfirmed: true),
            TransactionEntity(amount: 800, type: .debit, merchantRaw: "APOLLO PHARMACY", merchantName: "Apollo Pharmacy", categorySlug: "health", date: daysAgo(5), source: .sms, confidence: 0.90, isConfirmed: true),

            // 7 days ago
            TransactionEntity(amount: 25_000, type: .debit, merchantRaw: "RENT TRANSFER", merchantName: "House Rent", categorySlug: "rent", date: daysAgo(7), source: .manual, confidence: 1.0, isConfirmed: true, isRecurring: true),
            TransactionEntity(amount: 199, type: .debit, merchantRaw: "SPOTIFY", merchantName: "Spotify", categorySlug: "subscriptions", date: daysAgo(7), source: .email, confidence: 0.99, isConfirmed: true, isRecurring: true),

            // 10 days ago
            TransactionEntity(amount: 3_400, type: .debit, merchantRaw: "IRCTC RAIL", merchantName: "IRCTC", categorySlug: "travel", date: daysAgo(10), source: .email, confidence: 0.95, isConfirmed: true),
            TransactionEntity(amount: 620, type: .debit, merchantRaw: "SWIGGY", merchantName: "Swiggy", categorySlug: "food", date: daysAgo(10), source: .upi, confidence: 0.95, isConfirmed: true),

            // 12 days ago - needs review
            TransactionEntity(amount: 2_199, type: .debit, merchantRaw: "BATA INDIA 0012", merchantName: "Bata India", categorySlug: "others", date: daysAgo(12), source: .sms, confidence: 0.42, isConfirmed: false),
            TransactionEntity(amount: 499, type: .debit, merchantRaw: "UNKNOWN MERCHANT", merchantName: "Unknown", categorySlug: "others", date: daysAgo(12), source: .sms, confidence: 0.35, isConfirmed: false),

            // 14 days ago
            TransactionEntity(amount: 15_000, type: .debit, merchantRaw: "HDFC BANK EMI", merchantName: "HDFC Bank EMI", categorySlug: "emi", date: daysAgo(14), source: .sms, confidence: 0.93, isConfirmed: true, isRecurring: true),
            TransactionEntity(amount: 8_000, type: .debit, merchantRaw: "GROWW MF SIP", merchantName: "Groww SIP", categorySlug: "investments", date: daysAgo(14), source: .email, confidence: 0.97, isConfirmed: true, isRecurring: true),

            // 20 days ago
            TransactionEntity(amount: 1_800, type: .debit, merchantRaw: "MAKEMYTRIP", merchantName: "MakeMyTrip", categorySlug: "travel", date: daysAgo(20), source: .email, confidence: 0.94, isConfirmed: true),
            TransactionEntity(amount: 299, type: .debit, merchantRaw: "NOTION.SO", merchantName: "Notion", categorySlug: "subscriptions", date: daysAgo(20), source: .email, confidence: 0.95, isConfirmed: true, isRecurring: true),

            // Last month samples
            TransactionEntity(amount: 1_20_000, type: .credit, merchantRaw: "SALARY ACME CORP", merchantName: "Acme Corp Salary", categorySlug: "salary", date: daysAgo(31), source: .sms, confidence: 0.88, isConfirmed: true),
            TransactionEntity(amount: 22_000, type: .debit, merchantRaw: "RENT TRANSFER", merchantName: "House Rent", categorySlug: "rent", date: daysAgo(35), source: .manual, confidence: 1.0, isConfirmed: true),
            TransactionEntity(amount: 5_200, type: .debit, merchantRaw: "SWIGGY", merchantName: "Swiggy", categorySlug: "food", date: daysAgo(33), source: .upi, confidence: 0.95, isConfirmed: true),
            TransactionEntity(amount: 3_100, type: .debit, merchantRaw: "AMAZON", merchantName: "Amazon", categorySlug: "shopping", date: daysAgo(38), source: .sms, confidence: 0.92, isConfirmed: true),
            TransactionEntity(amount: 2_400, type: .debit, merchantRaw: "UBER", merchantName: "Uber", categorySlug: "travel", date: daysAgo(40), source: .upi, confidence: 0.97, isConfirmed: true),
        ]
    }
}
