import Foundation

/// How a run's time of day is written: the hour and minute in the person's own style, so a 24-hour region reads
/// "13:10" and a 12-hour one "1:10 PM". A log line adds the seconds, and a moment on another day adds its date.
public enum RunClock {
    public static func time(_ date: Date, seconds: Bool = false, calendar: Calendar = .current, locale: Locale = .current) -> String {
        format(date, template: seconds ? "jmmss" : "jmm", calendar: calendar, locale: locale)
    }

    /// The time alone for today, with the date in front for any other day: "13:10", or "2 Nov, 13:10".
    public static func moment(_ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        calendar.isDate(date, inSameDayAs: now)
            ? time(date, calendar: calendar, locale: locale)
            : format(date, template: "dMMMjmm", calendar: calendar, locale: locale)
    }

    private static func format(_ date: Date, template: String, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: locale) ?? "HH:mm"
        return formatter.string(from: date)
    }
}
