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

    /// 相对时间展示（刚刚 / N 分钟前 / N 小时前 / N 天前）
    func relativeTimeString(reference: Date = .now) -> String {
        let seconds = Int(reference.timeIntervalSince(self))
        guard seconds > 0 else { return "刚刚" }

        if seconds < 60 {
            return "刚刚"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) 分钟前"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) 小时前"
        }

        let days = hours / 24
        if days < 7 {
            return "\(days) 天前"
        }

        return dateString
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

    /// 将分钟数格式化为紧凑的 h/m 格式
    var hourMinuteString: String {
        let hours = self / 60
        let minutes = self % 60

        if hours > 0, minutes > 0 {
            return "\(hours)h\(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(Swift.max(self, 0))m"
    }
}

extension String {
    /// 解析 h/m 时长表达式为分钟数，支持 `90`、`90m`、`2h`、`2h30m`
    var parsedHourMinuteDuration: Int? {
        let normalized = lowercased()
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }

        if normalized.allSatisfy(\.isNumber) {
            return Int(normalized)
        }

        var totalMinutes = 0
        var currentNumber = ""
        var consumedCharacter = false

        for character in normalized {
            if character.isNumber {
                currentNumber.append(character)
                continue
            }

            guard let value = Int(currentNumber) else { return nil }

            switch character {
            case "h":
                totalMinutes += value * 60
            case "m":
                totalMinutes += value
            default:
                return nil
            }

            currentNumber = ""
            consumedCharacter = true
        }

        guard currentNumber.isEmpty, consumedCharacter, totalMinutes > 0 else {
            return nil
        }

        return totalMinutes
    }
}
