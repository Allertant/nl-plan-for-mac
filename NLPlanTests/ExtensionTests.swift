import Testing
import Foundation
@testable import NLPlan

// MARK: - Date Extension Tests

@Suite("Date Extension Tests")
struct DateExtensionTests {

    @Test("startOfDay 返回当天的 00:00:00")
    func testStartOfDay() {
        let date = DateComponents(calendar: .current, year: 2026, month: 4, day: 14, hour: 15, minute: 30).date!
        let start = date.startOfDay
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start)
        #expect(components.hour == 0)
        #expect(components.minute == 0)
        #expect(components.second == 0)
    }

    @Test("isToday 对当前时间返回 true")
    func testIsToday() {
        #expect(Date.now.isToday == true)
    }

    @Test("dateString 格式正确")
    func testDateString() {
        let date = DateComponents(calendar: .current, year: 2026, month: 4, day: 14).date!
        #expect(date.dateString == "2026-04-14")
    }

    @Test("isSameDay 正确判断同一天")
    func testIsSameDay() {
        let calendar = Calendar.current
        let d1 = calendar.date(from: DateComponents(year: 2026, month: 4, day: 14, hour: 10))!
        let d2 = calendar.date(from: DateComponents(year: 2026, month: 4, day: 14, hour: 22))!
        let d3 = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!

        #expect(d1.isSameDay(as: d2) == true)
        #expect(d1.isSameDay(as: d3) == false)
    }

    @Test("relativeTimeString 返回刚刚")
    func testRelativeTimeJustNow() {
        let reference = DateComponents(calendar: .current, year: 2026, month: 4, day: 14, hour: 12, minute: 0, second: 0).date!
        let date = reference.addingTimeInterval(-20)
        #expect(date.relativeTimeString(reference: reference) == "刚刚")
    }

    @Test("relativeTimeString 返回分钟前")
    func testRelativeTimeMinutesAgo() {
        let reference = DateComponents(calendar: .current, year: 2026, month: 4, day: 14, hour: 12, minute: 0, second: 0).date!
        let date = reference.addingTimeInterval(-8 * 60)
        #expect(date.relativeTimeString(reference: reference) == "8 分钟前")
    }

    @Test("relativeTimeString 返回小时前")
    func testRelativeTimeHoursAgo() {
        let reference = DateComponents(calendar: .current, year: 2026, month: 4, day: 14, hour: 12, minute: 0, second: 0).date!
        let date = reference.addingTimeInterval(-3 * 60 * 60)
        #expect(date.relativeTimeString(reference: reference) == "3 小时前")
    }
}

// MARK: - Int Extension Tests

@Suite("Int Duration Extension Tests")
struct IntDurationTests {

    @Test("0 秒 → 00:00:00")
    func testZeroSeconds() {
        #expect(0.durationString == "00:00:00")
    }

    @Test("65 秒 → 00:01:05")
    func test65Seconds() {
        #expect(65.durationString == "00:01:05")
    }

    @Test("3661 秒 → 01:01:01")
    func test3661Seconds() {
        #expect(3661.durationString == "01:01:01")
    }

    @Test("shortDurationString 小于 1 小时")
    func testShortDurationUnderHour() {
        #expect(1800.shortDurationString == "30m")
    }

    @Test("shortDurationString 大于 1 小时")
    func testShortDurationOverHour() {
        #expect(5400.shortDurationString == "1h30m")
    }
}
