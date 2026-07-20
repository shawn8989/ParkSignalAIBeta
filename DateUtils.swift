import Foundation

/// Date/time helpers used across ParkSignal AI.
///
/// Centralizes common calendar math so views/services don't re‑implement:
/// - Constructing a date at a specific hour/minute for "today" relative to a reference date
/// - Parsing simple "HH:mm" strings
/// - Converting a `Date`'s weekday into a 0..6 index (Sun=0)
/// - Extracting hour/minute components
/// - Combining a calendar date with the time of another date
/// - Formatting countdowns for UI labels
enum DateUtils {
    /// Build a date at the given hour/minute on the same calendar day as `ref`.
    static func todayAt(hour: Int, minute: Int, ref: Date = Date()) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: ref)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return Calendar.current.date(from: comps) ?? ref
    }

    /// Convert a date's weekday to 0..6 where Sunday = 0.
    static func weekdayIndex0_6(for date: Date) -> Int {
        (Calendar.current.component(.weekday, from: date) + 6) % 7
    }

    /// Extract the hour/minute from a date.
    static func hourMinute(of date: Date) -> (Int, Int) {
        let cal = Calendar.current
        return (cal.component(.hour, from: date), cal.component(.minute, from: date))
    }

    /// Parse a simple "HH:mm" string into hour/minute.
    static func parseHHmm(_ s: String) -> (Int, Int)? {
        let parts = s.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), (0..<24).contains(h),
              let m = Int(parts[1]), (0..<60).contains(m) else { return nil }
        return (h, m)
    }

    /// Combine the calendar date from `date` with the time components from `timeFrom`.
    static func combine(date: Date, timeFrom: Date) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = cal.component(.hour, from: timeFrom)
        comps.minute = cal.component(.minute, from: timeFrom)
        comps.second = 0
        return cal.date(from: comps) ?? date
    }

    /// Human‑friendly countdown string used in list cells (e.g., "1h 20m", "5m 10s").
    static func countdownString(to date: Date, from now: Date = Date()) -> String {
        let interval = max(0, Int(date.timeIntervalSince(now)))
        let minutes = interval / 60
        let hours = minutes / 60
        let days = hours / 24
        if days > 0 {
            let remH = hours % 24
            return "\(days)d\(remH > 0 ? " \(remH)h" : "")"
        } else if hours > 0 {
            let remM = minutes % 60
            return "\(hours)h\(remM > 0 ? " \(remM)m" : "")"
        } else if minutes > 0 {
            let secs = interval % 60
            return "\(minutes)m\(secs > 0 ? " \(secs)s" : "")"
        } else {
            return "now"
        }
    }
}
