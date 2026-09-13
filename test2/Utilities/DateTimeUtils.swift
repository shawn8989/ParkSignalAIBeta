import Foundation

/// Centralized date/time helpers for consistent formatting and scheduling across the app.
///
/// Notes:
/// - Weekday indices follow the project convention: 0 = Sunday ... 6 = Saturday.
/// - Overnight windows are handled by adding 24h to the end if `end <= start` for the same day.
/// - All functions are pure and thread-safe.
nonisolated enum DateTimeUtils {
    /// Parse a string in the form "HH:mm" into hour/minute.
    /// Returns nil for invalid or out-of-range input.
    static func parseHHmm(_ s: String) -> (hour: Int, minute: Int)? {
        let parts = s.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return (h, m)
    }

    /// Construct a Date at today with the provided hour/minute in the given reference day.
    static func todayAt(hour: Int, minute: Int, ref: Date = Date(), calendar: Calendar = .current) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: ref)
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return calendar.date(from: comps) ?? ref
    }

    /// Project-wide weekday index where 0 = Sunday ... 6 = Saturday.
    static func weekdayIndex0_6(_ date: Date, calendar: Calendar = .current) -> Int {
        // Apple: 1=Sunday ... 7=Saturday; convert to 0..6
        return (calendar.component(.weekday, from: date) + 6) % 7
    }

    /// Format only the time portion using a configurable style (default .short).
    static func timeOnly(_ date: Date, style: DateFormatter.Style = .short) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = style
        return f.string(from: date)
    }

    /// Format a time window, adjusting end forward by 24h when it is before or equal to start (overnight windows).
    static func timeWindowDescription(start: Date, end: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        var endAdj = end
        if endAdj <= start { endAdj = endAdj.addingTimeInterval(24 * 60 * 60) }
        return "\(f.string(from: start)) - \(f.string(from: endAdj))"
    }

    /// General date formatting helper.
    static func formatted(_ date: Date, dateStyle: DateFormatter.Style = .none, timeStyle: DateFormatter.Style = .short) -> String {
        let f = DateFormatter()
        f.dateStyle = dateStyle
        f.timeStyle = timeStyle
        return f.string(from: date)
    }

    /// Find the next occurrence of a weekly time (hour/minute) constrained to specific days of week.
    /// - Parameters:
    ///   - daysOfWeek: Allowed days (0 = Sun ... 6 = Sat). Empty returns nil.
    ///   - hour/minute: Target time of day.
    ///   - now: Starting point.
    ///   - lookaheadDays: How many days ahead to search (default 14).
    /// - Returns: The next future Date strictly greater than `now`, or nil if none within the window.
    static func nextOccurrence(daysOfWeek: [Int], hour: Int, minute: Int, from now: Date = Date(), calendar: Calendar = .current, lookaheadDays: Int = 14) -> Date? {
        guard !daysOfWeek.isEmpty else { return nil }
        let validDays = daysOfWeek.filter { 0...6 ~= $0 }
        guard !validDays.isEmpty else { return nil }

        var best: Date? = nil
        for offset in 0...max(0, lookaheadDays) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let w = weekdayIndex0_6(day, calendar: calendar)
            guard validDays.contains(w) else { continue }
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = hour; comps.minute = minute; comps.second = 0
            guard let candidate = calendar.date(from: comps) else { continue }
            if candidate <= now { continue }
            if best == nil || candidate < best! { best = candidate }
            // No need to continue scanning this day once we found a candidate
            break
        }
        return best
    }

    /// Human-readable countdown string like "1h 23m", "5m 10s", or "now".
    static func countdownString(to target: Date, from now: Date = Date()) -> String {
        let interval = max(0, Int(target.timeIntervalSince(now)))
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

    /// Whether a recurring restriction window is active at `now`.
    ///
    /// - Parameters:
    ///   - days: active weekdays, 0 = Sunday … 6 = Saturday. **Empty means every day.**
    /// Correctly handles overnight windows (end <= start) that began the PREVIOUS day —
    /// e.g. "No Parking 22:00–06:00 on Fri" is active at Sat 02:00 (the Friday-night
    /// window that runs into Saturday morning), which the naive same-day check missed.
    static func isWindowActive(startHour: Int, startMinute: Int,
                               endHour: Int, endMinute: Int,
                               days: [Int], now: Date, calendar: Calendar = .current) -> Bool {
        let daySet = days.isEmpty ? Set(0...6) : Set(days.filter { (0...6).contains($0) })
        guard !daySet.isEmpty else { return false }
        // Anchor the window to today (offset 0) and yesterday (offset -1) so an overnight
        // window that started the previous day is still detected in its early-morning tail.
        for offset in [0, -1] {
            guard let refDay = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let refWeekday = weekdayIndex0_6(refDay, calendar: calendar)
            guard daySet.contains(refWeekday) else { continue }
            let start = todayAt(hour: startHour, minute: startMinute, ref: refDay, calendar: calendar)
            var end = todayAt(hour: endHour, minute: endMinute, ref: refDay, calendar: calendar)
            if end <= start { end = end.addingTimeInterval(24 * 60 * 60) }
            if now >= start && now <= end { return true }
        }
        return false
    }
}
