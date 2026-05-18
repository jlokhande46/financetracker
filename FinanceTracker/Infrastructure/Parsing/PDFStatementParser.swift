import Foundation
import PDFKit

// MARK: - PDFStatementParser
// Real PDF parser using PDFKit. Extracts text, then runs row-based regex
// patterns to detect transactions across major Indian bank statement formats.

struct PDFParseResult {
    var transactions: [TransactionEntity]
    var detectedBank: String?
    var statementMonth: Date?
    var totalDebit: Decimal
    var totalCredit: Decimal
    var unparsedLineCount: Int
    // Credit-card statement fields
    var dueDate: Date?
    var statementDate: Date?
    var totalDue: Decimal?
    var minimumDue: Decimal?
    var accountLast4: String?
}

final class PDFStatementParser {

    static let shared = PDFStatementParser()

    private let normalizer = MerchantNormalizer.shared
    private let classifier = CategoryClassifier.shared

    // MARK: - Public entry point

    func parse(url: URL) -> PDFParseResult? {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let pdf = PDFDocument(url: url) else { return nil }
        let fullText = extractText(from: pdf)
        guard !fullText.isEmpty else { return nil }

        let bank = detectBank(in: fullText)
        let lines = fullText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var transactions: [TransactionEntity] = []
        var unparsed = 0

        for line in lines {
            if let txn = parseTransactionLine(line, bank: bank) {
                transactions.append(txn)
            } else if looksLikeTransactionLine(line) {
                unparsed += 1
            }
        }

        let totalDebit  = transactions.filter(\.isDebit).reduce(Decimal(0))  { $0 + $1.amount }
        let totalCredit = transactions.filter(\.isCredit).reduce(Decimal(0)) { $0 + $1.amount }

        return PDFParseResult(
            transactions: transactions,
            detectedBank: bank,
            statementMonth: detectStatementMonth(in: fullText),
            totalDebit: totalDebit,
            totalCredit: totalCredit,
            unparsedLineCount: unparsed,
            dueDate: extractDueDate(in: fullText),
            statementDate: extractStatementDate(in: fullText),
            totalDue: extractLabelledAmount(label: #"(?:total\s+amount\s+due|total\s+due|amount\s+due)"#, in: fullText),
            minimumDue: extractLabelledAmount(label: #"(?:minimum\s+amount\s+due|minimum\s+due|min(?:imum)?\s+due)"#, in: fullText),
            accountLast4: extractAccountLast4(in: fullText, bank: bank)
        )
    }

    // MARK: - Due-date & statement-field extraction

    private func extractDueDate(in text: String) -> Date? {
        if let raw = matchDueDate(in: text) {
            return sanitisedDueDate(raw)
        }
        return nil
    }

    /// Discard parses that landed implausibly far from "now". If the regex captured
    /// a date months in the past (year mis-parsed, fragment grabbed from elsewhere),
    /// try shifting it to the current/next year. If even that fails, return nil so
    /// the user isn't shown "Due 943 days ago".
    private func sanitisedDueDate(_ candidate: Date) -> Date? {
        let cal = Calendar.current
        let now = Date()
        let diffDays = (cal.dateComponents([.day], from: now, to: candidate).day ?? 0)

        // Plausible: 60 days in past (just-overdue) to 60 days in future
        if diffDays >= -60 && diffDays <= 60 { return candidate }

        // Try same day-month in the current year
        var comps = cal.dateComponents([.day, .month], from: candidate)
        comps.year = cal.component(.year, from: now)
        if let shifted = cal.date(from: comps) {
            let shiftedDiff = (cal.dateComponents([.day], from: now, to: shifted).day ?? 0)
            if shiftedDiff >= -60 && shiftedDiff <= 60 { return shifted }
            // If even current-year placement is in the recent past, advance to next year
            if shiftedDiff < -60 {
                comps.year = cal.component(.year, from: now) + 1
                if let nextYear = cal.date(from: comps) { return nextYear }
            }
        }
        return nil
    }

    private func matchDueDate(in text: String) -> Date? {
        // Patterns ordered by specificity
        let patterns: [(String, [String])] = [
            // "Payment Due Date : 27 May 2026"
            (#"(?i)(?:payment\s+)?due\s+date\s*[:\-]?\s*(\d{1,2}[- /][A-Za-z]{3,9}[- /]\d{2,4})"#,
             ["d-MMM-yyyy","d/MMM/yyyy","d MMM yyyy","d-MMMM-yyyy","d/MMMM/yyyy","d MMMM yyyy",
              "dd-MMM-yyyy","dd/MMM/yyyy","dd MMM yyyy","dd-MMM-yy","dd/MMM/yy","dd MMM yy"]),
            // "Due Date : 02 Jun 2026"
            (#"(?i)due\s+date\s*[:\-]?\s*(\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4})"#,
             ["d MMM yyyy","dd MMM yyyy","d MMMM yyyy","dd MMMM yyyy"]),
            // "Due Date : 27/05/2026"
            (#"(?i)(?:payment\s+)?due\s+date\s*[:\-]?\s*(\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4})"#,
             ["dd/MM/yyyy","d/M/yyyy","dd-MM-yyyy","dd/MM/yy"]),
            // "June 2, 2026" (ICICI style)
            (#"(?i)due\s+date\s*[:\-]?\s*([A-Za-z]{3,9}\s+\d{1,2},\s*\d{4})"#,
             ["MMMM d, yyyy","MMM d, yyyy"]),
        ]
        return firstDateMatch(patterns: patterns, in: text)
    }

    private func extractStatementDate(in text: String) -> Date? {
        let patterns: [(String, [String])] = [
            (#"(?i)statement\s+date\s*[:\-]?\s*(\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4})"#,
             ["d MMM yyyy","dd MMM yyyy","d MMMM yyyy","dd MMMM yyyy"]),
            (#"(?i)statement\s+date\s*[:\-]?\s*(\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4})"#,
             ["dd/MM/yyyy","dd-MM-yyyy","dd/MM/yy"]),
        ]
        return firstDateMatch(patterns: patterns, in: text)
    }

    private func extractLabelledAmount(label: String, in text: String) -> Decimal? {
        // Matches: <label> : Rs. 1,234.56  OR  <label> : 1,234.56
        let pattern = "\(label)\\s*[:\\-]?\\s*(?:Rs\\.?|INR)?\\s*([\\d,]+(?:\\.\\d{2})?)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: text)
        else { return nil }
        let str = String(text[r]).replacingOccurrences(of: ",", with: "")
        return Decimal(string: str)
    }

    private func extractAccountLast4(in text: String, bank: String?) -> String? {
        // Ordered most-specific → least-specific. The first match wins, so put the
        // patterns that target the last 4 digits of a masked card number first.
        let patterns = [
            // "XXXX XXXX XXXX 6624" — fully masked card number
            #"X{4}\s*X{4}\s*X{4}\s*(\d{4})\b"#,
            // "Card ending 6624" / "Card ending in 6624"
            #"(?i)(?:card|account)\s+ending\s+(?:in\s+)?(\d{4})\b"#,
            // "Card No. ending 6624"
            #"(?i)card\s+(?:no\.?\s+)?ending\s+(?:in\s+)?(\d{4})\b"#,
            // "Card Number 4477XXXXXXXX6624" — digits and X's mixed
            #"(?i)card\s+(?:no\.?|number)?\s*\d{0,4}[xX]+(\d{4})\b"#,
            // "A/c *6311" / "A/C XX6311"
            #"(?i)a/?c\s*[*xX]+(\d{4})\b"#,
            // "Account number ending 8708" / "Account 8708"
            #"(?i)account\s+(?:no\.?\s+|number\s+)?(?:ending\s+(?:in\s+)?)?(?:[xX*]+)?(\d{4})\b"#,
            // Last resort: "ending 6624" anywhere
            #"(?i)ending\s+(?:in\s+)?(?:[xX]+\s*)?(\d{4})\b"#,
            // Fall-back generic "Card 6624" (single 4-digit after card keyword)
            #"(?i)card\s+(\d{4})\b(?!\s*\d)"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges >= 2,
               let r = Range(match.range(at: 1), in: text) {
                return String(text[r])
            }
        }
        return nil
    }

    private func firstDateMatch(patterns: [(String, [String])], in text: String) -> Date? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_IN")
        for (pattern, formats) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: text)
            else { continue }
            let raw = String(text[r]).trimmingCharacters(in: .whitespaces)
            for fmt in formats {
                df.dateFormat = fmt
                if let date = df.date(from: raw) { return date }
            }
        }
        return nil
    }

    // MARK: - Text extraction

    private func extractText(from pdf: PDFDocument) -> String {
        var combined = ""
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i),
                  let pageText = page.string else { continue }
            combined += pageText + "\n"
        }
        return combined
    }

    // MARK: - Bank detection

    private func detectBank(in text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("hdfc bank")   { return "HDFC" }
        if lower.contains("icici bank")  { return "ICICI" }
        if lower.contains("state bank")  { return "SBI" }
        if lower.contains("axis bank")   { return "Axis" }
        if lower.contains("kotak")       { return "Kotak" }
        if lower.contains("yes bank")    { return "Yes Bank" }
        if lower.contains("idfc")        { return "IDFC" }
        if lower.contains("indusind")    { return "IndusInd" }
        if lower.contains("rbl")         { return "RBL" }
        return nil
    }

    // MARK: - Statement month detection

    private func detectStatementMonth(in text: String) -> Date? {
        let pattern = #"(?:statement|period|from)[:\s-]*([A-Za-z]{3,9})\s+(\d{4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 3,
              let monthRange = Range(match.range(at: 1), in: text),
              let yearRange = Range(match.range(at: 2), in: text)
        else { return nil }

        let monthName = String(text[monthRange])
        let yearStr = String(text[yearRange])

        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        if let date = df.date(from: "\(monthName) \(yearStr)") { return date }
        df.dateFormat = "MMM yyyy"
        return df.date(from: "\(monthName) \(yearStr)")
    }

    // MARK: - Transaction line detection

    private func looksLikeTransactionLine(_ line: String) -> Bool {
        let hasDate = line.range(of: #"\d{1,2}[/\-][A-Za-z0-9]{2,9}[/\-]\d{2,4}|\d{1,2}\s+[A-Za-z]{3,9}\s+\d{2,4}"#,
                                  options: .regularExpression) != nil
        let hasAmount = line.range(of: #"(?:\d{1,3}(?:[,\s]\d{3})+(?:\.\d{1,2})?)|(?:\d+\.\d{2})|(?:\d{4,})"#,
                                    options: .regularExpression) != nil
        return hasDate && hasAmount
    }

    private func parseTransactionLine(_ line: String, bank: String?) -> TransactionEntity? {
        // Extract date
        guard let (date, dateEnd) = extractDate(in: line) else { return nil }

        // Extract amounts (last two decimal-bearing numbers are usually amount + balance)
        let amounts = extractAmounts(in: line)
        guard !amounts.isEmpty else { return nil }

        // The narration sits between the date and the first amount
        let lineNS = line as NSString
        let amountStart = amounts[0].range.location
        guard dateEnd < amountStart else { return nil }

        let narrationLength = amountStart - dateEnd
        guard narrationLength > 0 else { return nil }

        let narration = lineNS.substring(with: NSRange(location: dateEnd, length: narrationLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "|*:- \t"))

        guard !narration.isEmpty else { return nil }
        guard isValidMerchantNarration(narration) else { return nil }
        guard !isJunkNarration(narration) else { return nil }

        // Determine debit/credit (with how-confident-we-are-about-direction)
        let inferred = inferAmountAndType(amounts: amounts, line: line, bank: bank)
        guard inferred.amount > 0 else { return nil }

        let normalizedMerchant = normalizer.normalize(narration)

        // CC Payment shortcut: if narration screams "card payment" AND we inferred credit,
        // bypass the normal classifier and tag as transfer-type cc_payment.
        let lower = line.lowercased()
        let isCCPayment = inferred.type == .credit &&
            (lower.contains("cc payment") || lower.contains("bppy") ||
             lower.contains("card payment") || lower.contains("payment received") ||
             lower.contains("payment thank you"))

        let categorySlug: String
        let categoryConfidence: Double
        if isCCPayment {
            categorySlug = "cc_payment"
            categoryConfidence = 1.0
        } else {
            let classification = classifier.classify(
                merchantName: normalizedMerchant,
                amount: inferred.amount,
                type: inferred.type,
                rawContent: line
            )
            categorySlug = classification.categorySlug
            categoryConfidence = classification.confidence
        }

        // Final confidence is the LOWER of category-confidence and direction-confidence.
        let finalConfidence = min(categoryConfidence, inferred.directionConfidence)

        return TransactionEntity(
            id: UUID(),
            amount: inferred.amount,
            type: inferred.type,
            merchantRaw: narration,
            merchantName: normalizedMerchant,
            categorySlug: categorySlug,
            date: date,
            source: .pdf,
            confidence: finalConfidence,
            isConfirmed: finalConfidence >= 0.85,
            rawContent: line
        )
    }

    // MARK: - Date extraction

    private struct DateMatch {
        let date: Date
        let nsRange: NSRange
    }

    private func extractDate(in line: String) -> (Date, Int)? {
        let patterns: [(String, [String])] = [
            (#"\d{2}[/-]\d{2}[/-]\d{4}"#,          ["dd/MM/yyyy", "dd-MM-yyyy"]),
            (#"\d{2}[/-]\d{2}[/-]\d{2}"#,          ["dd/MM/yy", "dd-MM-yy"]),
            (#"\d{2}\s+[A-Za-z]{3}\s+\d{4}"#,      ["dd MMM yyyy"]),
            (#"\d{2}\s+[A-Za-z]{3}\s+\d{2}"#,      ["dd MMM yy"]),
            (#"\d{2}[/-][A-Za-z]{3}[/-]\d{4}"#,    ["dd/MMM/yyyy", "dd-MMM-yyyy"]),
            (#"\d{2}[/-][A-Za-z]{3}[/-]\d{2}"#,    ["dd/MMM/yy", "dd-MMM-yy"]),
        ]

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_IN")
        let lineNS = line as NSString

        for (pattern, formats) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range) else { continue }
            let matchedString = lineNS.substring(with: match.range)
            for format in formats {
                df.dateFormat = format
                if let date = df.date(from: matchedString) {
                    var end = NSMaxRange(match.range)
                    // Consume an optional time "HH:MM" or "HH:MM:SS" trailing the date
                    if end < lineNS.length {
                        let tail = lineNS.substring(from: end)
                        if let timeRegex = try? NSRegularExpression(pattern: #"^[\s|]*\d{1,2}:\d{2}(?::\d{2})?"#),
                           let timeMatch = timeRegex.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)) {
                            end += timeMatch.range.length
                        }
                    }
                    return (date, end)
                }
            }
        }
        return nil
    }

    // MARK: - Junk-line filter

    /// Lines that look like transactions (have date + amount) but are actually
    /// statement metadata, fees, or running balances we don't want as transactions.
    private static let junkSubstrings: [String] = [
        "finance charge", "fin charge", "fin chg",
        "interest charge", "interest debit",
        "late payment", "late fee",
        "joining fee", "annual fee", "membership fee", "renewal fee",
        "service tax", "service charge",
        "convenience fee", "processing fee",
        "overlimit", "over limit",
        "cash advance fee",
        "fuel surcharge",
        "previous balance", "opening balance", "closing balance",
        "carry forward", "balance carried forward",
        "total amount due", "minimum amount due", "amount due",
        "available credit", "available limit", "credit limit",
        "payment due date", "statement date",
        " gst ", " igst ", " cgst ", " sgst ",
        // HDFC/ICICI statements embed the GST rate in the narration as "IGST-VPS...-RATE 18.0".
        // The "18.0" (the rate %) is mistaken for an amount; filter the whole line.
        "igst-",
    ]

    private func isJunkNarration(_ narration: String) -> Bool {
        let padded = " \(narration.lowercased()) "
        return Self.junkSubstrings.contains(where: { padded.contains($0) })
    }

    private func isValidMerchantNarration(_ narration: String) -> Bool {
        guard narration.count >= 3 else { return false }
        // Must contain at least one letter (rejects pure-number lines)
        guard narration.range(of: "[A-Za-z]{2,}", options: .regularExpression) != nil else { return false }
        return true
    }

    // MARK: - Amount extraction

    private struct AmountMatch {
        let value: Decimal
        let range: NSRange
        let hasCRSuffix: Bool
        let hasDRSuffix: Bool
    }

    private func extractAmounts(in line: String) -> [AmountMatch] {
        // Match amounts only when they're clearly amounts:
        //   (a) comma-separated numbers with optional decimal: 1,000 or 1,000.00
        //   (b) decimal-only numbers: 100.00, 100.5
        // We deliberately do NOT match bare 4-digit integers (would capture years like 2026)
        // and do NOT allow space as a thousands separator — PDFKit column spacing produces
        // patterns like "2 026.00" from the year 2026, which would otherwise be misread as ₹2,026.
        let pattern = #"((?:\d{1,3}(?:[,]\d{3})+(?:\.\d{1,2})?)|(?:\d{1,5}\.\d{1,2}))\s*(Cr|Dr|CR|DR)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, range: range)
        let ns = line as NSString

        return matches.compactMap { match -> AmountMatch? in
            guard match.numberOfRanges >= 2 else { return nil }
            let amtStr = ns.substring(with: match.range(at: 1))
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: " ", with: "")
            guard let val = Decimal(string: amtStr) else { return nil }

            var hasCR = false, hasDR = false
            if match.numberOfRanges >= 3, match.range(at: 2).location != NSNotFound {
                let suffix = ns.substring(with: match.range(at: 2)).uppercased()
                hasCR = suffix == "CR"
                hasDR = suffix == "DR"
            }
            return AmountMatch(value: val, range: match.range, hasCRSuffix: hasCR, hasDRSuffix: hasDR)
        }
    }

    /// Result of inference includes a confidence in the direction itself.
    /// Low directionConfidence means we guessed (likely a savings/current-account row
    /// where the empty column was stripped during text extraction).
    private struct InferenceResult {
        let amount: Decimal
        let type: TransactionType
        let directionConfidence: Double  // 0.0 – 1.0
    }

    private func inferAmountAndType(amounts: [AmountMatch], line: String, bank: String? = nil) -> InferenceResult {
        guard !amounts.isEmpty else {
            return InferenceResult(amount: 0, type: .debit, directionConfidence: 0)
        }

        // 1. Explicit Cr/Dr suffix on the amount — most reliable, BUT only trust it
        //    when there are ≤3 amounts on the row. Federal-style savings statements
        //    show 4 amounts per row (withdrawal, deposit, balance, with CR on the
        //    balance) — there the CR refers to balance state, not transaction
        //    direction. Column detection in step 4 handles that case correctly.
        if amounts.count <= 3 {
            if let cr = amounts.first(where: { $0.hasCRSuffix }) {
                return InferenceResult(amount: cr.value, type: .credit, directionConfidence: 1.0)
            }
            if let dr = amounts.first(where: { $0.hasDRSuffix }) {
                return InferenceResult(amount: dr.value, type: .debit, directionConfidence: 1.0)
            }
        }

        // 2. SBI CC — last non-space char on the row is 'C' (credit) or 'D' (debit)
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        if trimmedLine.hasSuffix(" C") || trimmedLine.hasSuffix("\tC") {
            let chosen = firstNonZero(in: amounts.dropLast()) ?? amounts[0]
            return InferenceResult(amount: chosen.value, type: .credit, directionConfidence: 1.0)
        }
        if trimmedLine.hasSuffix(" D") || trimmedLine.hasSuffix("\tD") {
            let chosen = firstNonZero(in: amounts.dropLast()) ?? amounts[0]
            return InferenceResult(amount: chosen.value, type: .debit, directionConfidence: 1.0)
        }

        // 3. HDFC CC (Tata Neu / Regalia) — '+' sign appears before the amount, sometimes
        // separated by currency markers ("₹", "Rs.", "INR") and/or whitespace.
        // PDFKit renders ₹ as the letter "C" on HDFC statements, so "C" is also accepted here.
        // NeuCoins lines like "+ 4 C 295.00" don't match because "4" sits between + and C.
        // Match: + followed by only whitespace / currency until end-of-segment.
        if let first = amounts.first {
            let lineNS = line as NSString
            let beforeAmount = lineNS.substring(to: first.range.location)
            let beforePattern = #"\+\s*(?:₹|C|Rs\.?|INR)?\s*$"#
            if beforeAmount.range(of: beforePattern, options: .regularExpression) != nil {
                return InferenceResult(amount: first.value, type: .credit, directionConfidence: 1.0)
            }
            // Also handle '+' appearing right AFTER the amount (sign column on the right).
            let afterStart = NSMaxRange(first.range)
            if afterStart < lineNS.length {
                let after = lineNS.substring(from: afterStart)
                let afterPattern = #"^\s*(?:₹|Rs\.?|INR)?\s*\+"#
                if after.range(of: afterPattern, options: .regularExpression) != nil {
                    return InferenceResult(amount: first.value, type: .credit, directionConfidence: 1.0)
                }
            }
        }

        // 4. Federal Bank / HDFC Savings — two columns (Withdrawal | Deposit | Balance).
        // If PDFKit preserved an explicit 0.00 in the empty column, column position tells
        // direction: index 0 = withdrawal (debit), index 1 = deposit (credit).
        let nonBalance = Array(amounts.dropLast())
        if nonBalance.count >= 2 {
            let nonZeroIndices = nonBalance.indices.filter { nonBalance[$0].value > 0 }
            if nonZeroIndices.count == 1, let idx = nonZeroIndices.first {
                let amount = nonBalance[idx].value
                let type: TransactionType = idx == 0 ? .debit : .credit
                return InferenceResult(amount: amount, type: type, directionConfidence: 0.9)
            }
        }

        // 5. Strict credit keywords. CC-payment phrasings are very high-confidence —
        // these only ever appear on rows where the cardholder paid down their bill.
        let lower = line.lowercased()
        let ccPaymentKeywords = [
            "cc payment", "card payment",
            "bppy cc", "bppy/", "bppy ",
            "payment received", "payment thank you", "payment - thank you",
            "auto debit-cc payment", "neft cr", "imps cr",
            "credit card payment", "bill payment received"
        ]
        if ccPaymentKeywords.contains(where: { lower.contains($0) }) {
            let chosen = firstNonZero(in: nonBalance) ?? amounts[0]
            return InferenceResult(amount: chosen.value, type: .credit, directionConfidence: 1.0)
        }
        let strictCreditKeywords = ["salary credit", "salary credited",
                                    "refund", "cashback", "reversal", "interest credit",
                                    "imps in/", "neft in/", "rtgs in/", "by transfer-",
                                    "credited by"]
        if strictCreditKeywords.contains(where: { lower.contains($0) }) {
            let chosen = firstNonZero(in: nonBalance) ?? amounts[0]
            return InferenceResult(amount: chosen.value, type: .credit, directionConfidence: 0.8)
        }

        // 6. Default — debit.
        // On HDFC CC statements the '+' rule is exhaustive: credits always show '+ C amount'
        // (green in the PDF). Reaching this step without a '+' match means it is definitively
        // a debit, so we can use high confidence. Other formats lack that guarantee.
        let chosen = firstNonZero(in: nonBalance) ?? amounts[0]
        let debitConfidence: Double = bank == "HDFC" ? 0.85 : 0.4
        return InferenceResult(amount: chosen.value, type: .debit, directionConfidence: debitConfidence)
    }

    private func firstNonZero<S: Sequence>(in amounts: S) -> AmountMatch? where S.Element == AmountMatch {
        amounts.first(where: { $0.value > 0 })
    }
}
