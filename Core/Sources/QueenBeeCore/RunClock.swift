import Foundation
import Synchronization

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

    /// How long something has been going, short: "40s", "2m 10s", "1h 05m".
    public static func span(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        let hours = whole / 3600, minutes = whole % 3600 / 60, rest = whole % 60
        if hours > 0 { return "\(hours)h " + String(format: "%02dm", minutes) }
        if minutes > 0 { return "\(minutes)m " + String(format: "%02ds", rest) }
        return "\(rest)s"
    }

    /// How long a run took: "42 sec", "3 min 5 sec", "1 hr 4 min".
    public static func length(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start).rounded()))
        if seconds < 60 { return "\(seconds) sec" }
        if seconds < 3600 { return "\(seconds / 60) min \(seconds % 60) sec" }
        return "\(seconds / 3600) hr \(seconds % 3600 / 60) min"
    }

    /// One formatter per way of writing, made the first time it is asked for: a log can ask hundreds of times a redraw.
    private static let formatters = Mutex<[String: DateFormatter]>([:])

    private static func format(_ date: Date, template: String, calendar: Calendar, locale: Locale) -> String {
        let key = [template, locale.identifier, "\(calendar.identifier)", calendar.timeZone.identifier].joined(separator: "|")
        return formatters.withLock { made in
            let formatter = made[key] ?? {
                let formatter = DateFormatter()
                formatter.locale = locale
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: locale) ?? "HH:mm"
                made[key] = formatter
                return formatter
            }()
            return formatter.string(from: date)
        }
    }
}
