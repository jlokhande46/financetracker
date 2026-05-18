import Foundation

struct ParsedSMSResult {
    var amount: Decimal
    var type: TransactionType
    var merchantRaw: String
    var last4: String?
    var date: Date?
    var upiRef: String?
    var bankRef: String?
    var rawText: String
}

/// SMS parser with bank-specific format detection.
/// Each parser is tuned to a real SMS format observed from that bank/card.
final class SMSParser {

    static let shared = SMSParser()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_IN")
        return f
    }()

    // Compiled regexes are expensive; cache them for the lifetime of the singleton.
    private static var regexCache: [String: NSRegularExpression] = [:]
    private static let regexCacheLock = NSLock()

    private func compiledRegex(_ pattern: String) -> NSRegularExpression? {
        Self.regexCacheLock.lock()
        defer { Self.regexCacheLock.unlock() }
        if let cached = Self.regexCache[pattern] { return cached }
        let regex = try? NSRegularExpression(pattern: pattern)
        Self.regexCache[pattern] = regex
        return regex
    }

    func parse(_ message: String) -> ParsedSMSResult? {
        let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)

        // Specific (high-precision) parsers first
        if let r = parseHDFCSavingsSent(msg)             { return r }
        if let r = parseHDFCSavingsCredited(msg)         { return r }
        if let r = parseFederalBankReceived(msg)         { return r }
        if let r = parseHDFCCreditCardTxn(msg)           { return r }
        if let r = parseHDFCCreditCardSpent(msg)         { return r }
        if let r = parseICICICreditCard(msg)             { return r }
        if let r = parseSBICreditCard(msg)               { return r }

        // Legacy fallbacks
        if let r = parseHDFCGeneric(msg)                 { return r }
        if let r = parseICICIGeneric(msg)                { return r }
        if let r = parseSBIGeneric(msg)                  { return r }
        if let r = parseAxisGeneric(msg)                 { return r }
        if let r = parseKotakGeneric(msg)                { return r }
        if let r = parseYesBankGeneric(msg)              { return r }
        if let r = parseUPIGeneric(msg)                  { return r }
        if let r = parseGenericDebit(msg)                { return r }
        if let r = parseGenericCredit(msg)               { return r }

        return nil
    }

    // MARK: - HDFC Savings — "Sent Rs.X From HDFC Bank A/C *XXXX To MERCHANT On DD/MM/YY Ref XXX"

    private func parseHDFCSavingsSent(_ msg: String) -> ParsedSMSResult? {
        let pattern = #"(?is)Sent\s+Rs\.?\s*([\d,]+(?:\.\d+)?)\s*From\s+HDFC\s+Bank\s+A/?C\s+\*?(\d{4})\s*To\s+([^\n]+?)\s*On\s+(\d{2}/\d{2}/\d{2,4})\s*Ref\s+(\d+)"#
        guard let r = match(pattern, in: msg) else { return nil }
        guard let amount = parseAmount(r[1]) else { return nil }
        return ParsedSMSResult(
            amount: amount,
            type: .debit,
            merchantRaw: r[3].trimmingCharacters(in: .whitespacesAndNewlines),
            last4: r[2],
            date: parseDate(r[4], formats: ["dd/MM/yy", "dd/MM/yyyy"]),
            upiRef: r[5],
            bankRef: nil,
            rawText: msg
        )
    }

    // MARK: - HDFC Savings Credit — "Credit Alert! Rs.X credited to HDFC Bank A/c XXNNNN on DD-MM-YY from VPA xxx (UPI nnn)"

    private func parseHDFCSavingsCredited(_ msg: String) -> ParsedSMSResult? {
        let pattern = #"(?is)(?:Credit\s+Alert!?\s*)?Rs\.?\s*([\d,]+(?:\.\d+)?)\s+credited\s+to\s+HDFC\s+Bank\s+A/?c\s+X+(\d{4})\s+on\s+(\d{2}-\d{2}-\d{2,4})\s+from\s+(?:VPA\s+)?(\S+)(?:\s*\(UPI\s+(\d+)\))?"#
        guard let r = match(pattern, in: msg) else { return nil }
        guard let amount = parseAmount(r[1]) else { return nil }
        return ParsedSMSResult(
            amount: amount,
            type: .credit,
            merchantRaw: r[4].trimmingCharacters(in: .whitespacesAndNewlines),
            last4: r[2],
            date: parseDate(r[3], formats: ["dd-MM-yy", "dd-MM-yyyy"]),
            upiRef: r[5].isEmpty ? nil : r[5],
            bankRef: nil,
            rawText: msg
        )
    }

    // MARK: - Federal Bank — "received INR X in your Account XXXXX. ... sent by NAME on Month DD, YYYY"

    private func parseFederalBankReceived(_ msg: String) -> ParsedSMSResult? {
        let pattern = #"(?is)received\s+INR\s+([\d,]+(?:\.\d+)?)\s+in\s+(?:your\s+)?Account\s+X+(\d{4}).*?sent\s+by\s+([^\n.]+?)\s+on\s+([A-Za-z]+\s+\d{1,2},\s*\d{4})"#
        guard let r = match(pattern, in: msg) else { return nil }
        guard let amount = parseAmount(r[1]) else { return nil }
        let date = parseDate(r[4], formats: ["MMM dd, yyyy", "MMMM dd, yyyy", "MMM d, yyyy", "MMMM d, yyyy"])
        return ParsedSMSResult(
            amount: amount,
            type: .credit,
            merchantRaw: r[3].trimmingCharacters(in: .whitespacesAndNewlines),
            last4: r[2],
            date: date,
            upiRef: nil,
            bankRef: nil,
            rawText: msg
        )
    }

    // MARK: - HDFC Credit Card Txn (Tata Neu Rupay UPI) — "Txn Rs.X On HDFC Bank Card XXXX At MERCHANT by UPI XXX On DD-MM"

    private func parseHDFCCreditCardTxn(_ msg: String) -> ParsedSMSResult? {
        let pattern = #"(?is)Txn\s+Rs\.?\s*([\d,]+(?:\.\d+)?)\s*On\s+HDFC\s+Bank\s+Card\s+(\d{4})\s*At\s+([^\n]+?)\s*by\s+UPI\s+(\d+)\s*On\s+(\d{2}-\d{2}(?:-\d{2,4})?)"#
        guard let r = match(pattern, in: msg) else { return nil }
        guard let amount = parseAmount(r[1]) else { return nil }
        let date = parseDate(r[5], formats: ["dd-MM-yyyy", "dd-MM-yy"]) ?? (r[5].count <= 5 ? fillCurrentYear(r[5]) : nil)
        return ParsedSMSResult(
            amount: amount,
            type: .debit,
            merchantRaw: r[3].trimmingCharacters(in: .whitespacesAndNewlines),
            last4: r[2],
            date: date,
            upiRef: r[4],
            bankRef: nil,
            rawText: msg
        )
    }

    // MARK: - HDFC Credit Card Spent (Regalia Gold) — "Spent Rs.X On HDFC Bank Card XXXX At MERCHANT On YYYY-MM-DD:HH:MM:SS"

    private func parseHDFCCreditCardSpent(_ msg: String) -> ParsedSMSResult? {
        let pattern = #"(?is)Spent\s+Rs\.?\s*([\d,]+(?:\.\d+)?)\s*On\s+HDFC\s+Bank\s+Card\s+(\d{4})\s*At\s+([^\n]+?)\s*On\s+(\d{4}-\d{2}-\d{2}(?::\d{2}:\d{2}:\d{2})?)"#
        guard let r = match(pattern, in: msg) else { return nil }
        guard let amount = parseAmount(r[1]) else { return nil }
        return ParsedSMSResult(
            amount: amount,
            type: .debit,
            merchantRaw: r[3].trimmingCharacters(in: .whitespacesAndNewlines),
            last4: r[2],
            date: parseDate(r[4], formats: ["yyyy-MM-dd:HH:mm:ss", "yyyy-MM-dd"]),
            upiRef: nil,
            bankRef: nil,
            rawText: msg
        )
    }

    // MARK: - ICICI Sapphiro — "INR X spent using ICICI Bank Card XXXX on DD-Mon-YY on MERCHANT . Avl Limit..."

    private func parseICICICreditCard(_ msg: String) -> ParsedSMSResult? {
        let pattern = #"(?is)INR\s+([\d,]+(?:\.\d+)?)\s+spent\s+using\s+ICICI\s+Bank\s+Card\s+X+(\d{4})\s+on\s+(\d{2}-[A-Za-z]{3}-\d{2,4})\s+on\s+([^.]+?)\s*\.\s*(?:Avl\s+Limit)?"#
        guard let r = match(pattern, in: msg) else { return nil }
        guard let amount = parseAmount(r[1]) else { return nil }
        return ParsedSMSResult(
            amount: amount,
            type: .debit,
            merchantRaw: r[4].trimmingCharacters(in: .whitespacesAndNewlines),
            last4: r[2],
            date: parseDate(r[3], formats: ["dd-MMM-yy", "dd-MMM-yyyy"]),
            upiRef: nil,
            bankRef: nil,
            rawText: msg
        )
    }

    // MARK: - SBI Credit Card — "Rs.X spent on your SBI Credit Card ending XXXX at MERCHANT on DD/MM/YY"

    private func parseSBICreditCard(_ msg: String) -> ParsedSMSResult? {
        let pattern = #"(?is)Rs\.?\s*([\d,]+(?:\.\d+)?)\s+spent\s+on\s+your\s+SBI\s+Credit\s+Card\s+ending\s+(\d{4})\s+at\s+([^\n]+?)\s+on\s+(\d{2}/\d{2}/\d{2,4})"#
        guard let r = match(pattern, in: msg) else { return nil }
        guard let amount = parseAmount(r[1]) else { return nil }
        return ParsedSMSResult(
            amount: amount,
            type: .debit,
            merchantRaw: r[3].trimmingCharacters(in: .whitespacesAndNewlines),
            last4: r[2],
            date: parseDate(r[4], formats: ["dd/MM/yy", "dd/MM/yyyy"]),
            upiRef: nil,
            bankRef: nil,
            rawText: msg
        )
    }

    // MARK: - Generic / legacy parsers (fallback)

    private func parseHDFCGeneric(_ msg: String) -> ParsedSMSResult? {
        guard msg.lowercased().contains("hdfc") else { return nil }
        if let r = match(#"(?i)(?:INR|Rs\.?)\s*([\d,]+\.?\d*)\s+(?:is\s+)?debited\s+from\s+(?:HDFC|your\s+HDFC)"#, in: msg) {
            return amountResult(r[1], type: .debit, rawText: msg)
        }
        if let r = match(#"(?i)(?:INR|Rs\.?)\s*([\d,]+\.?\d*)\s+credited\s+to\s+(?:HDFC|your\s+HDFC)"#, in: msg) {
            return amountResult(r[1], type: .credit, rawText: msg)
        }
        return nil
    }

    private func parseICICIGeneric(_ msg: String) -> ParsedSMSResult? {
        guard msg.lowercased().contains("icici") else { return nil }
        if let r = match(#"(?is)(?:Rs\.?|INR)\s*([\d,]+\.?\d*).*?debited.*?ICICI"#, in: msg) {
            return amountResult(r[1], type: .debit, rawText: msg)
        }
        if let r = match(#"(?is)(?:Rs\.?|INR)\s*([\d,]+\.?\d*).*?credited.*?ICICI"#, in: msg) {
            return amountResult(r[1], type: .credit, rawText: msg)
        }
        return nil
    }

    private func parseSBIGeneric(_ msg: String) -> ParsedSMSResult? {
        guard msg.lowercased().contains("sbi") || msg.contains("State Bank") else { return nil }
        if let r = match(#"(?is)(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s+debited\s+from\s+.*?SBI"#, in: msg) {
            return amountResult(r[1], type: .debit, rawText: msg)
        }
        if let r = match(#"(?is)(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s+credited\s+to\s+.*?SBI"#, in: msg) {
            return amountResult(r[1], type: .credit, rawText: msg)
        }
        return nil
    }

    private func parseAxisGeneric(_ msg: String) -> ParsedSMSResult? {
        guard msg.lowercased().contains("axis") else { return nil }
        if let r = match(#"(?i)(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s+debited"#, in: msg) {
            return amountResult(r[1], type: .debit, rawText: msg)
        }
        if let r = match(#"(?i)(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s+credited"#, in: msg) {
            return amountResult(r[1], type: .credit, rawText: msg)
        }
        return nil
    }

    private func parseKotakGeneric(_ msg: String) -> ParsedSMSResult? {
        guard msg.lowercased().contains("kotak") else { return nil }
        if let r = match(#"(?i)(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s+(?:has been\s+)?(?:debited|spent)"#, in: msg) {
            return amountResult(r[1], type: .debit, rawText: msg)
        }
        if let r = match(#"(?i)(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s+(?:has been\s+)?credited"#, in: msg) {
            return amountResult(r[1], type: .credit, rawText: msg)
        }
        return nil
    }

    private func parseYesBankGeneric(_ msg: String) -> ParsedSMSResult? {
        guard msg.lowercased().contains("yes bank") || msg.lowercased().contains("yesbank") else { return nil }
        if let r = match(#"(?i)(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s+debited"#, in: msg) {
            return amountResult(r[1], type: .debit, rawText: msg)
        }
        if let r = match(#"(?i)(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s+credited"#, in: msg) {
            return amountResult(r[1], type: .credit, rawText: msg)
        }
        return nil
    }

    private func parseUPIGeneric(_ msg: String) -> ParsedSMSResult? {
        let lowered = msg.lowercased()
        guard lowered.contains("upi") || lowered.contains("gpay") || lowered.contains("phonepe") || lowered.contains("paytm") else { return nil }

        let patterns: [(String, TransactionType)] = [
            (#"(?i)(?:[Pp]ayment|[Ss]ent)\s+of\s+(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+to\s+([^\n.]+?)(?:\s+via\s+UPI|\s+UPI|\.)"#, .debit),
            (#"(?i)(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:paid|sent)\s+(?:to\s+)?([^\n.]+?)(?:\s+via|\s+using|\s+through|\s+UPI|\.)"#, .debit),
            (#"(?i)(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+received\s+from\s+([^\n.]+?)(?:\s+via|\s+using|\s+UPI|\.)"#, .credit),
        ]
        for (pattern, type) in patterns {
            if let r = match(pattern, in: msg) {
                guard let amount = parseAmount(r[1]) else { continue }
                return ParsedSMSResult(
                    amount: amount,
                    type: type,
                    merchantRaw: r[2].trimmingCharacters(in: .whitespaces),
                    last4: nil,
                    date: nil,
                    upiRef: nil,
                    bankRef: nil,
                    rawText: msg
                )
            }
        }
        return nil
    }

    private func parseGenericDebit(_ msg: String) -> ParsedSMSResult? {
        let lowered = msg.lowercased()
        guard lowered.contains("debit") || lowered.contains("spent") || lowered.contains("paid") else { return nil }
        guard let r = match(#"(?i)(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:is\s+)?(?:debited|spent|charged)"#, in: msg) else { return nil }
        return amountResult(r[1], type: .debit, rawText: msg)
    }

    private func parseGenericCredit(_ msg: String) -> ParsedSMSResult? {
        let lowered = msg.lowercased()
        guard lowered.contains("credit") || lowered.contains("received") else { return nil }
        guard let r = match(#"(?i)(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:is\s+)?credited"#, in: msg) else { return nil }
        return amountResult(r[1], type: .credit, rawText: msg)
    }

    // MARK: - Helpers

    private func match(_ pattern: String, in text: String) -> [String]? {
        guard let regex = compiledRegex(pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range) else { return nil }
        var groups: [String] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            if r.location == NSNotFound {
                groups.append("")
            } else if let swiftRange = Range(r, in: text) {
                groups.append(String(text[swiftRange]))
            } else {
                groups.append("")
            }
        }
        return groups
    }

    private func parseAmount(_ str: String) -> Decimal? {
        Decimal(string: str.replacingOccurrences(of: ",", with: ""))
    }

    private func parseDate(_ str: String, formats: [String]) -> Date? {
        for format in formats {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: str) { return date }
        }
        return nil
    }

    /// When SMS gives only DD-MM (no year), pick the nearest year so a Dec-31 txn
    /// arriving Jan-1 isn't filed under next year.
    private func fillCurrentYear(_ ddMM: String) -> Date? {
        let cal = Calendar.current
        let now = Date()
        let currentYear = cal.component(.year, from: now)
        dateFormatter.dateFormat = "dd-MM-yyyy"
        guard let thisYear = dateFormatter.date(from: "\(ddMM)-\(currentYear)") else { return nil }
        let daysAhead = cal.dateComponents([.day], from: now, to: thisYear).day ?? 0
        if daysAhead > 30 {
            return dateFormatter.date(from: "\(ddMM)-\(currentYear - 1)") ?? thisYear
        }
        return thisYear
    }

    private func amountResult(_ amountStr: String, type: TransactionType, rawText: String) -> ParsedSMSResult? {
        guard let amount = parseAmount(amountStr) else { return nil }
        return ParsedSMSResult(
            amount: amount,
            type: type,
            merchantRaw: extractFallbackMerchant(from: rawText),
            last4: nil,
            date: nil,
            upiRef: nil,
            bankRef: nil,
            rawText: rawText
        )
    }

    private func extractFallbackMerchant(from msg: String) -> String {
        let patterns = [
            #"(?i)(?:to|at|for|from)\s+(?:VPA\s+)?([A-Za-z0-9@._\-\s]+?)(?:\s+on|\s+Ref|\s+UPI|\.|\n|$)"#,
            #"(?i)Info:\s*([A-Z0-9\s\-_]+?)(?:\s*Ref|$)"#,
        ]
        for pattern in patterns {
            if let r = match(pattern, in: msg), r.count > 1 {
                let candidate = r[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.count > 2 { return candidate }
            }
        }
        return ""
    }
}
