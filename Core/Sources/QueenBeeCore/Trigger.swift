import Foundation

/// What starts a run from a Start card without anyone pressing Run: the clock, or a file changing.
public struct Trigger: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case interval, daily, weekly, file
    }

    public var kind: Kind
    /// interval: minutes between runs.
    public var minutes: Int
    /// daily, weekly: the time of day.
    public var hour: Int
    public var minute: Int
    /// weekly: the days it runs on, as the calendar numbers them, with Sunday as 1.
    public var weekdays: [Int]
    /// file: a file or folder inside the project. A change to it, or to anything in it, starts a run.
    public var path: String

    public init(kind: Kind, minutes: Int = 60, hour: Int = 9, minute: Int = 0, weekdays: [Int] = [2], path: String = "") {
        self.kind = kind; self.minutes = minutes; self.hour = hour; self.minute = minute
        self.weekdays = weekdays; self.path = path
    }

    /// When the clock next starts a run after `date`. Nil for a file trigger, which the clock doesn't start.
    public func nextFire(after date: Date, calendar: Calendar = .current) -> Date? {
        let time = DateComponents(hour: min(max(hour, 0), 23), minute: min(max(minute, 0), 59), second: 0)
        switch kind {
        case .interval:
            return date.addingTimeInterval(Double(max(minutes, 1)) * 60)
        case .daily:
            return calendar.nextDate(after: date, matching: time, matchingPolicy: .nextTime)
        case .weekly:
            return weekdays.filter { (1...7).contains($0) }.compactMap { day -> Date? in
                var when = time
                when.weekday = day
                return calendar.nextDate(after: date, matching: when, matchingPolicy: .nextTime)
            }.min()
        case .file:
            return nil
        }
    }

    /// "Every 30 minutes", "Every day at 09:00", "Mon, Wed at 09:00", "When src changes".
    /// Times are always 24-hour here, so what the orchestrator reads never changes with the Mac's settings.
    /// The app shows `summary(in:)` to people instead.
    public var summary: String { summary(clock: String(format: "%02d:%02d", min(max(hour, 0), 23), min(max(minute, 0), 59))) }

    /// The same, with the time written the way `locale` writes it: "7:30 AM" on a 12-hour Mac, "07:30" on a 24-hour one.
    public func summary(in locale: Locale) -> String { summary(clock: Self.clock(hour: hour, minute: minute, in: locale)) }

    /// A time of day as `locale` writes it, for the summary and for the pickers.
    public static func clock(hour: Int, minute: Int, in locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var parts = DateComponents(year: 2001, month: 1, day: 1)
        parts.hour = min(max(hour, 0), 23)
        parts.minute = min(max(minute, 0), 59)
        let date = calendar.date(from: parts) ?? Date(timeIntervalSinceReferenceDate: 0)
        return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute())
    }

    /// Just the hour as `locale` writes it ("7 AM", "07"), for the hour picker.
    public static func hourLabel(_ hour: Int, in locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var parts = DateComponents(year: 2001, month: 1, day: 1)
        parts.hour = min(max(hour, 0), 23)
        let date = calendar.date(from: parts) ?? Date(timeIntervalSinceReferenceDate: 0)
        return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour())
    }

    /// Whether `locale` writes the hour on a 24-hour clock.
    public static func usesTwentyFourHours(_ locale: Locale) -> Bool {
        !clock(hour: 15, minute: 0, in: locale).contains(where: \.isLetter) // no AM/PM marker
    }

    private func summary(clock: String) -> String {
        switch kind {
        case .interval:
            let m = max(minutes, 1)
            if m % 60 == 0 { return m == 60 ? "Every hour" : "Every \(m / 60) hours" }
            return m == 1 ? "Every minute" : "Every \(m) minutes"
        case .daily:
            return "Every day at \(clock)"
        case .weekly:
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let days = weekdays.filter { (1...7).contains($0) }.sorted().map { names[$0 - 1] }
            return days.isEmpty ? "No day chosen" : "\(days.joined(separator: ", ")) at \(clock)"
        case .file:
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "No file chosen" : "When \(trimmed) changes"
        }
    }
}
