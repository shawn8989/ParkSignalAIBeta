// DEPRECATED: This file duplicated ParkingSpot status helpers and is no longer used.
// It is excluded from the build. You can safely delete this file.
#if false
import Foundation
import SwiftUI

extension ParkingSpot {
    /// True if, based on recorded restrictions, parking is not allowed right now.
    /// Considers .noParking and .streetCleaning windows for today (including overnight windows).
    var cannotParkNow: Bool {
        let now = Date()
        let cal = Calendar.current
        let weekday0_6 = (cal.component(.weekday, from: now) + 6) % 7 // Sun=0..Sat=6
        for r in restrictions {
            guard r.type == .noParking || r.type == .streetCleaning else { continue }
            guard r.daysOfWeek.isEmpty || r.daysOfWeek.contains(weekday0_6) else { continue }
            let start = combine(date: now, timeFrom: r.startTime)
            var end = combine(date: now, timeFrom: r.endTime)
            // Handle overnight (end before start means next day)
            if end <= start { end = end.addingTimeInterval(24*60*60) }
            if now >= start && now <= end { return true }
        }
        return false
    }

    /// A simple status color for map pins:
    /// - Green: currently parked here (active session)
    /// - Red: cannot park now (restriction window active)
    /// - Orange: upcoming restriction within 2 hours
    /// - Accent (blue): otherwise
    func pinColor(now: Date = Date()) -> Color {
        if parkSessions.contains(where: { $0.endedAt == nil }) { return .green }
        if cannotParkNow { return .red }
        if let next = nextRestrictionDate(from: now), next.timeIntervalSince(now) <= 2*60*60 { return .orange }
        return .accentColor
    }

    private func combine(date: Date, timeFrom: Date) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = cal.component(.hour, from: timeFrom)
        comps.minute = cal.component(.minute, from: timeFrom)
        comps.second = 0
        return cal.date(from: comps) ?? date
    }
}
#endif
