import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    // MARK: - Permission

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    // MARK: - Schedule daily reminders for a card statement

    func scheduleReminders(for statement: CardStatementEntity) {
        cancelReminders(for: statement.id)
        guard !statement.isPaid else { return }

        let center = UNUserNotificationCenter.current()
        let today = Calendar.current.startOfDay(for: Date())
        let due   = Calendar.current.startOfDay(for: statement.dueDate)
        guard due >= today else { return }

        let days = Calendar.current.dateComponents([.day], from: today, to: due).day ?? 0

        // Schedule one notification per day from today until due date (max 7 days ahead)
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
            let id = notificationId(statement.id, offset: offset)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    func cancelReminders(for statementId: UUID) {
        let ids = (0...6).map { notificationId(statementId, offset: $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Helpers

    private func notificationId(_ statementId: UUID, offset: Int) -> String {
        "card_due_\(statementId.uuidString)_d\(offset)"
    }

    private func formattedAmount(_ amount: Decimal) -> String {
        let d = Double(truncating: amount as NSDecimalNumber)
        if d >= 1_00_000 { return String(format: "%.1fL", d / 1_00_000) }
        if d >= 1_000    { return String(format: "%.0fK", d / 1_000) }
        return String(format: "%.0f", d)
    }
}
