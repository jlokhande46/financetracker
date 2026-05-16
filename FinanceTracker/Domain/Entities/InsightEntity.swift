import Foundation

struct InsightEntity: Identifiable, Equatable {
    let id: UUID
    var type: InsightType
    var title: String
    var body: String
    var amount: Decimal?
    var categorySlug: String?
    var date: Date
    var isRead: Bool
    var actionSlug: String?

    init(
        id: UUID = UUID(),
        type: InsightType,
        title: String,
        body: String,
        amount: Decimal? = nil,
        categorySlug: String? = nil,
        date: Date = Date(),
        isRead: Bool = false,
        actionSlug: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.amount = amount
        self.categorySlug = categorySlug
        self.date = date
        self.isRead = isRead
        self.actionSlug = actionSlug
    }
}

enum InsightType: String {
    case warning  = "warning"
    case positive = "positive"
    case neutral  = "neutral"
    case tip      = "tip"

    var icon: String {
        switch self {
        case .warning:  return "exclamationmark.triangle.fill"
        case .positive: return "checkmark.circle.fill"
        case .neutral:  return "info.circle.fill"
        case .tip:      return "lightbulb.fill"
        }
    }

    var color: String {
        switch self {
        case .warning:  return "#FFB545"
        case .positive: return "#00D09C"
        case .neutral:  return "#8E8E99"
        case .tip:      return "#7B6EF6"
        }
    }
}
