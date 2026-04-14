import Foundation

extension Date {
    /// 获取当天的起始时间
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// 是否是同一天
    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    /// 是否是今天
    var isToday: Bool {
        isSameDay(as: .now)
    }

    /// 格式化为 "yyyy-MM-dd"
    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }

    /// 格式化为 "HH:mm"
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }

    /// 格式化为 "MM/dd HH:mm"
    var shortDateTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: self)
    }
}

extension Int {
    /// 格式化秒数为 "HH:MM:SS"
    var durationString: String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let seconds = self % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// 格式化秒数为简短格式 "HH:MM" 或 "MM:SS"
    var shortDurationString: String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        if hours > 0 {
            return String(format: "%dh%dm", hours, minutes)
        }
        return String(format: "%dm", minutes)
    }
}
