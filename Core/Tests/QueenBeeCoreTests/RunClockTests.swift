import Foundation
import Testing
@testable import QueenBeeCore

@Suite struct RunClockTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: hour, minute: minute))!
    }

    @Test func aTwelveHourRegionGetsAmAndPm() {
        let text = RunClock.time(date(hour: 13, minute: 10), calendar: calendar, locale: Locale(identifier: "en_US"))
        #expect(text.hasPrefix("1:10"))
        #expect(text.contains("PM"))
    }

    @Test func aTwentyFourHourRegionGetsTheFullHour() {
        let text = RunClock.time(date(hour: 13, minute: 10), calendar: calendar, locale: Locale(identifier: "en_GB"))
        #expect(text == "13:10")
    }

    @Test func minutesKeepTheirLeadingZero() {
        let text = RunClock.time(date(hour: 9, minute: 5), calendar: calendar, locale: Locale(identifier: "en_GB"))
        #expect(text == "09:05")
    }

    @Test func aLogLineKeepsItsSeconds() {
        let at = date(hour: 13, minute: 10).addingTimeInterval(7)
        #expect(RunClock.time(at, seconds: true, calendar: calendar, locale: Locale(identifier: "en_GB")) == "13:10:07")
    }

    @Test func aMomentOnAnotherDaySaysWhichDay() {
        let gb = Locale(identifier: "en_GB")
        let at = date(hour: 13, minute: 10)
        #expect(RunClock.moment(at, now: at.addingTimeInterval(3600), calendar: calendar, locale: gb) == "13:10")
        let other = RunClock.moment(at, now: at.addingTimeInterval(86_400), calendar: calendar, locale: gb)
        #expect(other.contains("4") && other.contains("Mar") && other.contains("13:10"))
    }
}
