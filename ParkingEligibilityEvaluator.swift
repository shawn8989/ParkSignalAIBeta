// ParkingEligibilityEvaluator.swift
import Foundation
import CoreLocation

struct ParkingEligibility {
    let allowed: Bool
    let summary: String
    let warnings: [String]
    let nextRestriction: Date?
}

enum ParkingEligibilityEvaluator {
    static func evaluate(coordinate: CLLocationCoordinate2D, spotRestrictions: [Restriction], now: Date = Date()) async -> ParkingEligibility {
        // Bootstrap city dataset and fetch nearby sample restrictions
        await ParkingDataProvider.shared.bootstrapIfNeeded(currentLocation: coordinate)
        let city = ParkingDataProvider.shared.matchedCity?.cityName
        let cityItems = await ParkingDataProvider.shared.restrictionsNear(coordinate)

        // Merge spot rules and city rules into a common evaluation model
        var blocks: [String] = []
        var warns: [String] = []

        // Evaluate spot restrictions first (authoritative if present)
        for r in spotRestrictions {
            if isActive(r, at: now) {
                switch r.type {
                case .noParking, .streetCleaning:
                    blocks.append("\(r.type.displayName) in effect: \(DateTimeUtils.timeWindowDescription(start: r.startTime, end: r.endTime))")
                case .permit:
                    warns.append("Permit required during \(DateTimeUtils.timeWindowDescription(start: r.startTime, end: r.endTime))")
                case .metered:
                    warns.append("Metered parking until \(DateTimeUtils.timeOnly(r.endTime))")
                case .other:
                    break
                }
            }
        }

        // Evaluate city sample restrictions as hints (non-authoritative)
        for cr in cityItems {
            if isActive(cr, at: now) {
                switch cr.type {
                case .noParking, .streetCleaning:
                    blocks.append("\(cr.type.displayName) in effect (\(city ?? "city")): \(cr.startTime)-\(cr.endTime)")
                case .permit:
                    warns.append("Permit required (\(city ?? "city")) during \(cr.startTime)-\(cr.endTime)")
                case .metered:
                    warns.append("Metered parking (\(city ?? "city")) until \(cr.endTime)")
                case .other:
                    break
                }
            }
        }

        let allowed = blocks.isEmpty
        let next = nextRestrictionDate(spotRestrictions: spotRestrictions, cityRestrictions: cityItems, from: now)

        let summary: String
        if !allowed {
            summary = "Not recommended to park here now: \(blocks.first ?? "Restriction active")."
        } else if !warns.isEmpty {
            summary = "Allowed with caution: \(warns.first!)."
        } else if let n = next {
            let formatter = DateFormatter(); formatter.timeStyle = .short
            summary = "Allowed now. Next restriction at \(formatter.string(from: n))."
        } else {
            summary = "Allowed now."
        }

        return ParkingEligibility(allowed: allowed, summary: summary, warnings: warns, nextRestriction: next)
    }

    // MARK: - Helpers

    private static func isActive(_ r: Restriction, at now: Date) -> Bool {
        let cal = Calendar.current
        let weekday0_6 = (cal.component(.weekday, from: now) + 6) % 7
        guard r.daysOfWeek.isEmpty || r.daysOfWeek.contains(weekday0_6) else { return false }
        var start = DateTimeUtils.todayAt(hour: cal.component(.hour, from: r.startTime), minute: cal.component(.minute, from: r.startTime), ref: now)
        var end = DateTimeUtils.todayAt(hour: cal.component(.hour, from: r.endTime), minute: cal.component(.minute, from: r.endTime), ref: now)
        if end <= start { end = end.addingTimeInterval(24*60*60) }
        return now >= start && now <= end
    }

    private static func isActive(_ r: CityRestriction, at now: Date) -> Bool {
        let cal = Calendar.current
        let weekday0_6 = (cal.component(.weekday, from: now) + 6) % 7
        guard r.daysOfWeek.isEmpty || r.daysOfWeek.contains(weekday0_6) else { return false }
        guard let s = DateTimeUtils.parseHHmm(r.startTime), let e = DateTimeUtils.parseHHmm(r.endTime) else { return false }
        var start = DateTimeUtils.todayAt(hour: s.0, minute: s.1, ref: now)
        var end = DateTimeUtils.todayAt(hour: e.0, minute: e.1, ref: now)
        if end <= start { end = end.addingTimeInterval(24*60*60) }
        return now >= start && now <= end
    }

    private static func nextRestrictionDate(spotRestrictions: [Restriction], cityRestrictions: [CityRestriction], from now: Date) -> Date? {
        let cal = Calendar.current
        func weekdayIndex0_6(_ date: Date) -> Int { (cal.component(.weekday, from: date) + 6) % 7 }
        func hourMinute(_ date: Date) -> (Int, Int) { (cal.component(.hour, from: date), cal.component(.minute, from: date)) }
        var best: Date? = nil
        // Spot restrictions
        for r in spotRestrictions {
            let days = r.daysOfWeek
            if days.isEmpty { continue }
            let (h, m) = hourMinute(r.startTime)
            for offset in 0...13 {
                guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
                let w = weekdayIndex0_6(day)
                guard days.contains(w) else { continue }
                var comps = cal.dateComponents([.year, .month, .day], from: day)
                comps.hour = h; comps.minute = m; comps.second = 0
                guard let candidate = cal.date(from: comps) else { continue }
                if candidate <= now { continue }
                if best == nil || candidate < best! { best = candidate }
                break
            }
        }
        // City restrictions
        for cr in cityRestrictions {
            let days = cr.daysOfWeek
            if days.isEmpty { continue }
            guard let s = DateTimeUtils.parseHHmm(cr.startTime) else { continue }
            for offset in 0...13 {
                guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
                let w = weekdayIndex0_6(day)
                guard days.contains(w) else { continue }
                var comps = cal.dateComponents([.year, .month, .day], from: day)
                comps.hour = s.0; comps.minute = s.1; comps.second = 0
                guard let candidate = cal.date(from: comps) else { continue }
                if candidate <= now { continue }
                if best == nil || candidate < best! { best = candidate }
                break
            }
        }
        return best
    }
}
