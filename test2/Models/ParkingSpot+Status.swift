import Foundation

extension ParkingSpot {
    /// Returns the next start date of any restriction for this spot within the next 14 days.
    /// - Parameter now: Reference time (defaults to current date).
    /// - Returns: The next start `Date` strictly in the future, or nil if none found.
    func nextRestrictionDate(from now: Date = Date()) -> Date? {
        let cal = Calendar.current
        var best: Date? = nil
        for r in restrictions {
            // Empty days = applies every day (matches isActive semantics).
            let days = r.daysOfWeek.isEmpty ? Array(0...6) : r.daysOfWeek
            let hour = cal.component(.hour, from: r.startTime)
            let minute = cal.component(.minute, from: r.startTime)
            if let candidate = DateTimeUtils.nextOccurrence(daysOfWeek: days, hour: hour, minute: minute, from: now, calendar: cal, lookaheadDays: 14) {
                if best == nil || candidate < best! { best = candidate }
            }
        }
        return best
    }

    /// Whether a blocking restriction (No Parking / Street Cleaning) is active right now for this spot.
    /// - Parameter now: Reference time (defaults to current date).
    func isRestrictedNow(at now: Date = Date()) -> Bool {
        let cal = Calendar.current
        for r in restrictions where r.type == .noParking || r.type == .streetCleaning {
            let sh = cal.component(.hour, from: r.startTime)
            let sm = cal.component(.minute, from: r.startTime)
            let eh = cal.component(.hour, from: r.endTime)
            let em = cal.component(.minute, from: r.endTime)
            if DateTimeUtils.isWindowActive(startHour: sh, startMinute: sm, endHour: eh, endMinute: em,
                                            days: r.daysOfWeek, now: now, calendar: cal) {
                return true
            }
        }
        return false
    }
}
