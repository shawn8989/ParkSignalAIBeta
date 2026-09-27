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
        return DateTimeUtils.isWindowActive(startHour: cal.component(.hour, from: r.startTime),
                                            startMinute: cal.component(.minute, from: r.startTime),
                                            endHour: cal.component(.hour, from: r.endTime),
                                            endMinute: cal.component(.minute, from: r.endTime),
                                            days: r.daysOfWeek, now: now, calendar: cal)
    }

    private static func isActive(_ r: CityRestriction, at now: Date) -> Bool {
        guard let s = DateTimeUtils.parseHHmm(r.startTime), let e = DateTimeUtils.parseHHmm(r.endTime) else { return false }
        return DateTimeUtils.isWindowActive(startHour: s.hour, startMinute: s.minute,
                                            endHour: e.hour, endMinute: e.minute,
                                            days: r.daysOfWeek, now: now)
    }

    private static func nextRestrictionDate(spotRestrictions: [Restriction], cityRestrictions: [CityRestriction], from now: Date) -> Date? {
        let cal = Calendar.current
        func next(_ days: [Int], _ hour: Int, _ minute: Int) -> Date? {
            // Empty days mean "every day", matching `DateTimeUtils.isWindowActive`.
            DateTimeUtils.nextOccurrence(daysOfWeek: days.isEmpty ? Array(0...6) : days,
                                         hour: hour, minute: minute,
                                         from: now, calendar: cal, lookaheadDays: 13)
        }
        let spotStarts = spotRestrictions.compactMap { r in
            next(r.daysOfWeek, cal.component(.hour, from: r.startTime), cal.component(.minute, from: r.startTime))
        }
        let cityStarts = cityRestrictions.compactMap { cr in
            DateTimeUtils.parseHHmm(cr.startTime).flatMap { t in next(cr.daysOfWeek, t.hour, t.minute) }
        }
        return (spotStarts + cityStarts).min()
    }
}
