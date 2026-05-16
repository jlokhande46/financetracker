import Foundation

extension Date {
    var monthYear: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: self)
    }

    var shortMonthYear: String {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f.string(from: self)
    }

    var dayMonthYear: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f.string(from: self)
    }

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: self)
    }

    var relativeDay: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMM"
        return f.string(from: self)
    }

    var startOfMonth: Date {
        Calendar.current.dateInterval(of: .month, for: self)!.start
    }

    var endOfMonth: Date {
        Calendar.current.dateInterval(of: .month, for: self)!.end
    }

    static var currentMonthStart: Date { Date().startOfMonth }
    static var currentMonthEnd: Date { Date().endOfMonth }
}

extension DateFormatter {
    static let dayMonthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()
}
