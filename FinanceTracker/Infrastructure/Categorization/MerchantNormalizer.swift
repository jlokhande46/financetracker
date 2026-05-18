import Foundation

class MerchantNormalizer {
    static let shared = MerchantNormalizer()

    private let aliasMap: [String: String] = [
        // Amazon — ASSPL is Amazon Seller Services Pvt Ltd (marketplace)
        "AMZNPAY": "Amazon Pay", "AMAZON PAY": "Amazon Pay", "AMAZN": "Amazon",
        "AMAZON": "Amazon", "AMZN": "Amazon",
        "ASSPL": "Amazon", "ASPL": "Amazon",
        // Food delivery
        "SWGY": "Swiggy", "SWIGGY": "Swiggy", "SWIGGY ORDER": "Swiggy",
        "CAS*SWIGGY": "Swiggy", "CAS SWIGGY": "Swiggy",
        "ZOMTO": "Zomato", "ZOMATO": "Zomato",
        "BLINKIT": "Blinkit", "GROFERS": "Blinkit",
        "BIGBASKET": "BigBasket", "BIGBZR": "BigBasket",
        "ZEPTO": "Zepto", "ZEPTO MARKETPLACE": "Zepto", "ZEPTO MARKETPLACE PRIV": "Zepto",
        "ZEPTOMARKETPLACEPRIV": "Zepto", "ZEPTOMARKETPLACE": "Zepto",
        "DUNZO": "Dunzo",
        // Restaurants / Dining
        "DISTRICTDININGCYBS": "District Dining", "DISTRICT DINING": "District Dining",
        "DISTRICTDININGMPGS": "District Dining",
        "THEOBROMA": "Theobroma", "THEOBROMA FOODS": "Theobroma",
        "THEOBROMA FOODS PVT": "Theobroma",
        "JOSHH": "Joshh Cafe",
        "AMA CAFE": "Ama Cafe",
        "KAAFE": "Kaafe",
        // Hotels / Stays
        "THE HOSTELLER": "The Hosteller", "HOSTELLER": "The Hosteller",
        "ARCHES BY SALVUS": "Arches By Salvus", "ARCHES BY SALVUSRISHIKESH": "Arches By Salvus",
        // Lounge access
        "WWW LOUNGEONE AI": "Lounge One", "LOUNGEONE": "Lounge One",
        // Entertainment / Ticketing
        "BOOKMYSHOW": "BookMyShow", "PAY*BOOKMYSHOW": "BookMyShow",
        "NETFLIX": "Netflix", "NETFLIX.COM": "Netflix",
        "SPOTIFY": "Spotify", "SPOTIFY AB": "Spotify",
        "HOTSTAR": "Disney+ Hotstar", "DISNEY HOTSTAR": "Disney+ Hotstar",
        "PRIME VIDEO": "Amazon Prime", "AMAZON PRIME": "Amazon Prime",
        "YOUTUBE PREMIUM": "YouTube Premium",
        "SONY LIV": "SonyLIV", "SONYLIV": "SonyLIV",
        "ZEE5": "ZEE5", "VOOT": "VOOT",
        // Travel / Hotels
        "AGODAPANYPTELTD": "Agoda", "AGODA": "Agoda",
        "MAKEMYTRIP": "MakeMyTrip", "MMT": "MakeMyTrip",
        "GOIBIBO": "Goibibo", "CLEARTRIP": "Cleartrip",
        "YATRA": "Yatra",
        // Transport
        "UBER": "Uber", "UBER INDIA": "Uber", "UBER INDIA SYSTEMS": "Uber",
        "OLA": "Ola", "ANI TECHNOLOGIES": "Ola",
        "RAPIDO": "Rapido", "ROPPEN TRANSPORTATION": "Rapido",
        "REDBUS": "RedBus", "REDBUS INDIA": "RedBus",
        "CAS*REDBUS": "RedBus",
        "RAJKAMAL MOBILITY": "Rajkamal Mobility",
        "DMRC": "Delhi Metro", "BANGALORE METRO": "Metro",
        "BMTC": "BMTC Bus", "IRCTC": "IRCTC", "IRCTC RAIL": "IRCTC",
        // Fuel
        "BPCL": "BPCL Fuel", "IOC": "Indian Oil", "IOCL": "Indian Oil",
        "HPCL": "HPCL Fuel", "RELIANCE PETRO": "Reliance Fuel",
        // Shopping
        "MYNTRA": "Myntra", "FLIPKART": "Flipkart", "FK": "Flipkart",
        "MEESHO": "Meesho", "NYKAA": "Nykaa",
        "AJIO": "AJIO", "SNAPDEAL": "Snapdeal",
        // Telecom
        "AIRTEL": "Airtel", "BHARTI AIRTEL": "Airtel",
        "RELIANCE JIO": "Jio", "JIO": "Jio", "JIOMART": "JioMart",
        "VODAFONE": "Vi", "IDEA CELLULAR": "Vi",
        "BSNL": "BSNL",
        // Utilities
        "TATA POWER": "Tata Power", "BESCOM": "BESCOM",
        "MAHANAGAR GAS": "MGL Gas", "IGL": "IGL Gas",
        "JUSPAY": "Juspay", "BILL DESK": "BillDesk",
        // Finance
        "HDFC BANK": "HDFC Bank", "ICICI BANK": "ICICI Bank",
        "SBI": "SBI", "AXIS BANK": "Axis Bank",
        "ZERODHA": "Zerodha", "GROWW": "Groww",
        "PAYTM": "Paytm", "PHONEPE": "PhonePe", "GPAY": "Google Pay",
        // Health
        "APOLLO": "Apollo Pharmacy", "MEDPLUS": "MedPlus",
        "PHARMEASY": "PharmEasy", "1MG": "1mg",
        "CLINICO PET SCAN": "Clinico Pet Scan",
        // Grocery / Supermarket
        "JALARAM SUPER MARKET": "Jalaram Supermarket",
        // BookMyShow
        "PAYBOOKMYSHOW COM": "BookMyShow", "PAYBOOKMYSHOW": "BookMyShow",
    ]

    private let junkWords = ["POS", "INR", "TXN", "PURCHASE", "TRANSACTION", "PAYMENT", "DEBIT"]

    private let bankPrefixes = ["UPI-", "UPI/", "UPI ", "POS-", "POS ", "POS/", "BIL/", "ECS/",
                                 "NEFT-", "NEFT/", "RTGS-", "RTGS/", "IMPS-", "IMPS/", "ATM-", "ATM ",
                                 "PAY*", "PAY-", "CAS*", "CAS-", "CCD*"]

    private let corpSuffixes = [" PVT LTD", " PRIVATE LIMITED", " PVT-LTD", " PVT", " LIMITED", " LTD",
                                 " INDIA", " IN", " CO", " CORP", " CORPORATION", " PRIV", " PVT-"]

    func normalize(_ raw: String) -> String {
        // User-defined rules win over everything else — if the user once renamed
        // "Upi-jay-rent" to "Rent", every future occurrence should be "Rent".
        if let learned = MainActor.assumeIsolated({ MerchantRuleStore.shared.displayNameForMerchant(raw) }) {
            return learned
        }

        var cleaned = stripPrefixes(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        cleaned = stripVPAAndRefs(cleaned)
        cleaned = clean(cleaned)
        cleaned = stripCorpSuffixes(cleaned)

        let upper = cleaned.uppercased()

        // Exact match
        if let mapped = aliasMap[upper] { return mapped }

        // Contains match (longest first)
        let sortedKeys = aliasMap.keys.sorted { $0.count > $1.count }
        for key in sortedKeys {
            if upper.contains(key) {
                return aliasMap[key]!
            }
        }

        // Take only first 3-4 meaningful words for display
        return shortTitleCase(cleaned)
    }

    private func stripPrefixes(_ raw: String) -> String {
        let upper = raw.uppercased()
        for prefix in bankPrefixes {
            if upper.hasPrefix(prefix) {
                return String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return raw
    }

    /// Strip VPA handles (anything after @) and trailing reference tokens like "-merchant-vpa-123"
    private func stripVPAAndRefs(_ raw: String) -> String {
        var result = raw
        // Anything from @ onwards (jlokhande46-2@okicici → "")
        if let at = result.firstIndex(of: "@") {
            result = String(result[..<at])
        }
        // Trailing "-token-token-token" segments (UPI ref hashes)
        result = result.replacingOccurrences(of: #"(?i)\s*-(?:pvt|ltd|merchant|vpa|upi|ref|txn|[a-z0-9]{6,})(?:-[a-z0-9]+)*\s*$"#, with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripCorpSuffixes(_ raw: String) -> String {
        var result = raw
        var upper = result.uppercased()
        var changed = true
        while changed {
            changed = false
            for suffix in corpSuffixes where upper.hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                upper = result.uppercased()
                changed = true
                break
            }
        }
        return result
    }

    private func clean(_ raw: String) -> String {
        var result = raw
        // Remove long digit runs (6+) which are typically UPI/Ref numbers
        result = result.replacingOccurrences(of: #"\d{6,}"#, with: "", options: .regularExpression)
        // Replace common separators with spaces
        result = result.replacingOccurrences(of: #"[/\\|*#_]"#, with: " ", options: .regularExpression)
        // Remove standalone junk words (word-boundary aware)
        for word in junkWords {
            result = result.replacingOccurrences(of: "\\b\(word)\\b", with: "", options: [.regularExpression, .caseInsensitive])
        }
        // Collapse multiple spaces / dashes
        result = result.replacingOccurrences(of: #"[\s-]{2,}"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: CharacterSet(charactersIn: " -"))
    }

    /// Title-case + truncate to first 3 meaningful words (shorter, SMS-style names)
    private func shortTitleCase(_ str: String) -> String {
        let words = str.split(whereSeparator: { $0 == " " || $0 == "-" })
            .map { String($0) }
            .filter { !$0.isEmpty }
        let trimmed = Array(words.prefix(3))
        return trimmed
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}
