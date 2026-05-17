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

    func scheduleReminders(for statement: CardStatementEntity) {
        cancelReminders(for: statement.id)
        guard !statement.isPaid else { return }

        let center = UNUserNotificationCenter.current()
        let today = Calendar.current.startOfDay(for: Date())
        let due   = Calendar.current.startOfDay(for: statement.dueDate)
        guard due >= today else { return }

        let days = Calendar.current.dateComponents([.day], from: today, to: due).day ?? 0

        for offset in 0...min(days, 6) {
            guard let fireDate = Calendar.current.date(byAdding: .day, value: offset, to: today) else { continue }
            var components = Calendar.current.dateComponents([.year, .month, .day], from: fireDate)
            components.hour = 9
            components.minute = 0

            let content = UNMutableNotificationContent()
            content.title = "Card Payment Due"
            content.sound = .default

            let daysLeft = days - offset
            let amountStr = "₹\(formattedAmount(statement.totalDue))"
            switch daysLeft {
            case 0:
                content.body = "\(statement.accountName) payment of \(amountStr) is due TODAY."
                content.interruptionLevel = .timeSensitive
            case 1:
                content.body = "\(statement.accountName) payment of \(amountStr) is due TOMORROW."
            default:
                content.body = "\(statement.accountName) — \(amountStr) due in \(daysLeft) days."
            }

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let id = cardNotificationId(statement.id, offset: offset)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    func cancelReminders(for statementId: UUID) {
        let ids = (0...6).map { cardNotificationId(statementId, offset: $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
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

    private func cardNotificationId(_ statementId: UUID, offset: Int) -> String {
        "card_due_\(statementId.uuidString)_d\(offset)"
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
