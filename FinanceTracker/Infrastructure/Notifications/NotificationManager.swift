import Foundation
import UserNotifications

final class NotificationManager: NSObject {
    static let shared = NotificationManager()
    private override init() { super.init() }

    // MARK: - Permission

    func requestPermission() {
        // Register as delegate so alerts display while the app is in the foreground.
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    // MARK: - Card due-date reminders

    /// Maximum days ahead of the current sweep we schedule a 9 AM reminder.
    /// iOS caps pending notifications at 64 per app; with up to 4 active cards
    /// + a 6 PM reminder layered into the last 3 days, 21 keeps us well under.
    /// Each daily sweep refreshes the schedule so longer cycles still get the
    /// next-day reminder when the user re-opens the app.
    private static let maxAMOffset = 21
    /// Trailing days before due that also get a 6 PM "increased frequency"
    /// reminder, on top of the standard 9 AM.
    private static let extraPMTrailingDays = 3

    /// Schedules the rolling daily reminders for an unpaid statement plus an
    /// extra evening reminder for the last 3 days before due. The full
    /// schedule is rebuilt each call — older requests for the same statement
    /// are cancelled first via `cancelReminders`.
    func scheduleReminders(for statement: CardStatementEntity) {
        cancelReminders(for: statement.id)
        guard !statement.isPaid else { return }

        let center = UNUserNotificationCenter.current()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let due   = cal.startOfDay(for: statement.dueDate)
        guard due >= today else { return }

        let daysToDue = cal.dateComponents([.day], from: today, to: due).day ?? 0
        let amountStr = "₹\(formattedAmount(statement.totalDue))"

        // 9 AM daily reminder for every day from today through due.
        let amCap = min(daysToDue, Self.maxAMOffset)
        for offset in 0...amCap {
            guard let fireDate = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            scheduleSingleReminder(
                center: center,
                statement: statement,
                fireDate: fireDate,
                hour: 9,
                slot: "am",
                offset: offset,
                daysLeft: daysToDue - offset,
                amountStr: amountStr
            )
        }

        // 6 PM extra reminder for the trailing days. Skip the due day's PM
        // slot — the AM timeSensitive notification already covers the day.
        let pmStart = max(0, daysToDue - Self.extraPMTrailingDays + 1)
        for offset in pmStart..<daysToDue {
            guard let fireDate = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            scheduleSingleReminder(
                center: center,
                statement: statement,
                fireDate: fireDate,
                hour: 18,
                slot: "pm",
                offset: offset,
                daysLeft: daysToDue - offset,
                amountStr: amountStr
            )
        }
    }

    private func scheduleSingleReminder(
        center: UNUserNotificationCenter,
        statement: CardStatementEntity,
        fireDate: Date,
        hour: Int,
        slot: String,
        offset: Int,
        daysLeft: Int,
        amountStr: String
    ) {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: fireDate)
        components.hour = hour
        components.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "Card Payment Due"
        content.sound = .default
        content.threadIdentifier = "card-due-\(statement.id.uuidString)"

        switch daysLeft {
        case 0:
            content.body = "\(statement.accountName) payment of \(amountStr) is due TODAY."
            content.interruptionLevel = .timeSensitive
        case 1:
            content.body = "\(statement.accountName) payment of \(amountStr) is due TOMORROW."
            if slot == "pm" { content.interruptionLevel = .timeSensitive }
        default:
            content.body = "\(statement.accountName) — \(amountStr) due in \(daysLeft) days."
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let id = cardNotificationId(statement.id, offset: offset, slot: slot)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func cancelReminders(for statementId: UUID) {
        var ids: [String] = []
        for offset in 0...Self.maxAMOffset {
            ids.append(cardNotificationId(statementId, offset: offset, slot: "am"))
            ids.append(cardNotificationId(statementId, offset: offset, slot: "pm"))
        }
        ids.append(billGeneratedNotificationId(statementId))
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// One-shot "Bill Generated" alert fired immediately after BillCycleManager
    /// creates a new CardStatement. Distinct from the recurring payment
    /// reminders — surfaces the freshly-billed amount + due date once, then
    /// the daily reminders pick up from there.
    func fireBillGeneratedAlert(for statement: CardStatementEntity) {
        let content = UNMutableNotificationContent()
        content.title = "Bill Generated"
        content.sound = .default
        content.threadIdentifier = "card-due-\(statement.id.uuidString)"
        let amount = "₹\(formattedAmount(statement.totalDue))"
        let dueFmt = DateFormatter()
        dueFmt.dateFormat = "d MMM"
        content.body = "\(statement.accountName): \(amount) billed. Due \(dueFmt.string(from: statement.dueDate))."

        // Small delay so the alert lands AFTER the user finishes interacting
        // with whatever action triggered the sweep (app launch, txn save).
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 4, repeats: false)
        let request = UNNotificationRequest(
            identifier: billGeneratedNotificationId(statement.id),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Budget alerts

    /// Checks every active budget and fires a notification when it crosses 80 % or 100 %.
    /// Each threshold fires at most once per budget period — deduplication is keyed by
    /// budget ID + threshold level + current period identifier so the user isn't spammed
    /// on every app open.
    func scheduleBudgetAlerts(_ budgets: [BudgetEntity]) {
        guard UserDefaults.standard.object(forKey: "budgetAlertsEnabled") as? Bool ?? true else { return }

        for budget in budgets where budget.isActive {
            let progress = budget.progress
            guard progress >= 0.8 else {
                // Below warning threshold — clear any stale dedup keys so the
                // alert fires again if the budget resets next period.
                resetBudgetDedupIfNewPeriod(budget)
                continue
            }

            let isOver  = progress >= 1.0
            let level   = isOver ? "over" : "warn"
            let dedupKey = budgetDedupKey(budget.id, level: level)

            // Only fire once per period per threshold level.
            guard UserDefaults.standard.string(forKey: dedupKey) != currentPeriodKey(for: budget) else { continue }

            let categoryName = CategoryEntity.find(slug: budget.categorySlug).name
            let content = UNMutableNotificationContent()
            content.sound = .default
            content.threadIdentifier = "budget-alerts"

            if isOver {
                let overage = budget.spent - budget.amount
                content.title = "Budget Exceeded"
                content.body = "\(categoryName) is over by ₹\(formattedAmount(overage)). Consider reviewing your spend."
                content.interruptionLevel = .timeSensitive
            } else {
                content.title = "Budget Alert"
                content.body = "\(categoryName) is 80% used — only ₹\(formattedAmount(budget.remaining)) left this period."
            }

            // Small delay so bulk imports don't trigger a flood of simultaneous alerts.
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
            let requestId = "budget_\(budget.id.uuidString)_\(level)"
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: requestId, content: content, trigger: trigger)
            )
            UserDefaults.standard.set(currentPeriodKey(for: budget), forKey: dedupKey)
        }
    }

    func cancelBudgetAlerts(for budgetId: UUID) {
        let ids = ["budget_\(budgetId.uuidString)_warn", "budget_\(budgetId.uuidString)_over"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UserDefaults.standard.removeObject(forKey: budgetDedupKey(budgetId, level: "warn"))
        UserDefaults.standard.removeObject(forKey: budgetDedupKey(budgetId, level: "over"))
    }

    // MARK: - Private helpers

    private func cardNotificationId(_ statementId: UUID, offset: Int, slot: String) -> String {
        "card_due_\(statementId.uuidString)_d\(offset)_\(slot)"
    }

    private func billGeneratedNotificationId(_ statementId: UUID) -> String {
        "card_bill_gen_\(statementId.uuidString)"
    }

    private func budgetDedupKey(_ budgetId: UUID, level: String) -> String {
        "budget_alert_\(budgetId.uuidString)_\(level)"
    }

    /// A string that uniquely identifies the current period for this budget
    /// (e.g. "2025-M5" for May monthly, "2025-W20" for week 20 weekly).
    private func currentPeriodKey(for budget: BudgetEntity) -> String {
        let cal = Calendar.current
        let now = Date()
        switch budget.period {
        case .weekly:
            return "\(cal.component(.year, from: now))-W\(cal.component(.weekOfYear, from: now))"
        case .monthly:
            return "\(cal.component(.year, from: now))-M\(cal.component(.month, from: now))"
        case .annual:
            return "\(cal.component(.year, from: now))"
        }
    }

    private func resetBudgetDedupIfNewPeriod(_ budget: BudgetEntity) {
        for level in ["warn", "over"] {
            let key = budgetDedupKey(budget.id, level: level)
            if let stored = UserDefaults.standard.string(forKey: key),
               stored != currentPeriodKey(for: budget) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    private func formattedAmount(_ amount: Decimal) -> String {
        let d = NSDecimalNumber(decimal: amount).doubleValue
        if d >= 1_00_000 { return String(format: "%.1fL", d / 1_00_000) }
        if d >= 1_000    { return String(format: "%.0fK", d / 1_000) }
        return String(format: "%.0f", d)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Show notification banners even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
}
