import SwiftUI

/// A recurring obligation the user owes on a fixed cycle — rent, utilities,
/// CC bill, postpaid, gas, etc. Distinct from a `BudgetEntity` (which caps
/// spend) and a `CardStatementEntity` (which is auto-derived from CC txns).
/// The user explicitly defines each bill and its `dueDay`; the system tracks
/// which billing cycle was last paid and fires post-salary reminders for
/// any cycle still unpaid.
struct RecurringBillEntity: Identifiable, Equatable {
    let id: UUID
    var name: String
    var type: RecurringBillType
    /// Expected amount, optional because some bills (electricity / gas)
    /// vary month-to-month and the user may not want to commit a number.
    var amount: Decimal?
    var frequency: RecurringBillFrequency
    /// Day of month the bill is due (1-31). For bimonthly bills, this is
    /// the due day in the month the bill falls.
    var dueDay: Int
    var isActive: Bool
    /// Start of the most recent billing cycle the user marked as paid.
    /// `nil` means never paid via the app — every current/past cycle counts
    /// as unpaid.
    var lastPaidCycleStart: Date?
    var lastPaidDate: Date?
    /// Optional link to the TransactionEntity that paid this bill, so the
    /// user can see "Rent · Paid via HDFC transfer ₹25,000 on 5th".
    var lastPaidTransactionId: UUID?
    var notes: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        type: RecurringBillType,
        amount: Decimal? = nil,
        frequency: RecurringBillFrequency = .monthly,
        dueDay: Int,
        isActive: Bool = true,
        lastPaidCycleStart: Date? = nil,
        lastPaidDate: Date? = nil,
        lastPaidTransactionId: UUID? = nil,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.amount = amount
        self.frequency = frequency
        self.dueDay = dueDay
        self.isActive = isActive
        self.lastPaidCycleStart = lastPaidCycleStart
        self.lastPaidDate = lastPaidDate
        self.lastPaidTransactionId = lastPaidTransactionId
        self.notes = notes
        self.createdAt = createdAt
    }

    // MARK: - Cycle math

    /// The next-occurring due date (today or future) for this bill given its
    /// `dueDay` + `frequency`. For monthly bills this is the next dueDay this
    /// month or next; bimonthly steps by 2 months from the most recent past
    /// occurrence.
    var nextDueDate: Date { nextDueDate(after: Date()) }

    func nextDueDate(after reference: Date) -> Date {
        let cal = Calendar.current
        let refStart = cal.startOfDay(for: reference)
        var comps = cal.dateComponents([.year, .month], from: refStart)
        comps.day = min(dueDay, 28) // safe baseline; we'll snap up below
        var d = cal.date(from: comps) ?? refStart
        // Snap the day to the actual dueDay (handles 30/31 in shorter months).
        d = snapDay(dueDay, to: d, calendar: cal)
        let step: Int = frequency == .monthly ? 1 : 2
        while d < refStart {
            d = cal.date(byAdding: .month, value: step, to: d) ?? d
            d = snapDay(dueDay, to: d, calendar: cal)
        }
        return d
    }

    /// The start date of the billing cycle that ends at `nextDueDate`.
    /// A bill is "due this cycle" if `lastPaidCycleStart` is older than this.
    var currentCycleStart: Date {
        let cal = Calendar.current
        let step: Int = frequency == .monthly ? -1 : -2
        return cal.date(byAdding: .month, value: step, to: nextDueDate) ?? nextDueDate
    }

    /// True if the bill is still unpaid for the cycle that ends on
    /// `nextDueDate`. Used to filter the "due now" list and decide whether
    /// to schedule reminders.
    var isDueThisCycle: Bool {
        guard isActive else { return false }
        guard let lastPaid = lastPaidCycleStart else { return true }
        return lastPaid < currentCycleStart
    }

    var daysUntilDue: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day],
                                  from: cal.startOfDay(for: Date()),
                                  to: cal.startOfDay(for: nextDueDate)).day ?? 0
    }

    var isOverdue: Bool { isDueThisCycle && daysUntilDue < 0 }

    /// Snap a day-of-month to the closest valid day in the given month,
    /// clamping to the month's last day. So a bill with dueDay = 31 falls
    /// on Feb 28/29 in February, June 30 in June, etc.
    private func snapDay(_ day: Int, to date: Date, calendar: Calendar) -> Date {
        let range = calendar.range(of: .day, in: .month, for: date) ?? 1...28
        let clamped = min(day, range.upperBound - 1)
        var comps = calendar.dateComponents([.year, .month], from: date)
        comps.day = clamped
        return calendar.date(from: comps) ?? date
    }
}

enum RecurringBillType: String, Codable, CaseIterable, Identifiable {
    case rent
    case electricity
    case gas
    case postpaid
    case ccBill = "cc_bill"
    case internet
    case water
    case insurance
    case subscription
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rent:         return "Rent"
        case .electricity:  return "Electricity"
        case .gas:          return "Gas"
        case .postpaid:     return "Postpaid"
        case .ccBill:       return "Credit Card"
        case .internet:     return "Internet"
        case .water:        return "Water"
        case .insurance:    return "Insurance"
        case .subscription: return "Subscription"
        case .other:        return "Other"
        }
    }

    var icon: String {
        switch self {
        case .rent:         return "house.fill"
        case .electricity:  return "bolt.fill"
        case .gas:          return "flame.fill"
        case .postpaid:     return "phone.fill"
        case .ccBill:       return "creditcard.fill"
        case .internet:     return "wifi"
        case .water:        return "drop.fill"
        case .insurance:    return "shield.fill"
        case .subscription: return "repeat"
        case .other:        return "doc.text.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .rent:         return "#8B5CF6"
        case .electricity:  return "#3B82F6"
        case .gas:          return "#F97316"
        case .postpaid:     return "#A855F7"
        case .ccBill:       return "#A78BFA"
        case .internet:     return "#06B6D4"
        case .water:        return "#0EA5E9"
        case .insurance:    return "#84CC16"
        case .subscription: return "#EC4899"
        case .other:        return "#94A3B8"
        }
    }

    var color: Color { Color(hex: colorHex) }

    /// Used by the Mark-Paid sheet to filter the transaction picker to
    /// candidates the user is likely to have used to pay this bill.
    var likelyCategorySlugs: [String] {
        switch self {
        case .rent:         return ["rent", "transfer"]
        case .electricity:  return ["bills"]
        case .gas:          return ["bills"]
        case .postpaid:     return ["bills"]
        case .ccBill:       return ["cc_payment", "transfer"]
        case .internet:     return ["bills"]
        case .water:        return ["bills"]
        case .insurance:    return ["insurance", "bills"]
        case .subscription: return ["subscriptions"]
        case .other:        return []
        }
    }
}

enum RecurringBillFrequency: String, Codable, CaseIterable, Identifiable {
    case monthly, bimonthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monthly:   return "Monthly"
        case .bimonthly: return "Every 2 months"
        }
    }
}
