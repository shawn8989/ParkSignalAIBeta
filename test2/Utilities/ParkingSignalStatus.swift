import Foundation
import SwiftUI

// Unified color-coded parking signal states used across the app
enum ParkingSignalStatus: String, CaseIterable, Codable, Equatable {
    case green   // Safe to park now
    case red     // Illegal to park now (active restriction)
    case yellow  // Allowed now, but a restriction is approaching soon
    case blue    // Permit/ADA required
    case purple  // Meter / paid parking
    case gray    // Unknown or incomplete scan
}

extension ParkingSignalStatus {
    var color: Color {
        switch self {
        case .green:  return .green
        case .red:    return .red
        case .yellow: return .yellow
        case .blue:   return .blue
        case .purple: return .purple
        case .gray:   return .gray
        }
    }

    var iconName: String {
        switch self {
        case .green:  return "checkmark.circle.fill"
        case .red:    return "xmark.octagon.fill"
        case .yellow: return "exclamationmark.triangle.fill"
        case .blue:   return "person.badge.shield.checkmark"
        case .purple: return "dollarsign.circle.fill"
        case .gray:   return "questionmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .green:  return "Safe to Park"
        case .red:    return "Illegal Now"
        case .yellow: return "Restriction Soon"
        case .blue:   return "Permit/ADA Required"
        case .purple: return "Metered / Paid"
        case .gray:   return "Unknown"
        }
    }
}

// MARK: - Evaluation Engine

struct ParkingSignalEvaluator {
    // Priority: red > yellow > blue > purple > green > gray
    // leadMinutes controls the threshold for "soon" (yellow)

    static func status(for spot: ParkingSpot, now: Date = Date(), leadMinutes: Int = 15) -> ParkingSignalStatus {
        let cal = Calendar.current
        let weekday0_6 = (cal.component(.weekday, from: now) + 6) % 7

        // Helper to check active window for a Restriction on a given date
        func isActive(_ r: Restriction) -> Bool {
            // If days specified, require match
            if !r.daysOfWeek.isEmpty && !r.daysOfWeek.contains(weekday0_6) { return false }
            let sh = cal.component(.hour, from: r.startTime)
            let sm = cal.component(.minute, from: r.startTime)
            let eh = cal.component(.hour, from: r.endTime)
            let em = cal.component(.minute, from: r.endTime)
            var start = todayAt(hour: sh, minute: sm, ref: now)
            var end = todayAt(hour: eh, minute: em, ref: now)
            if end <= start { end = end.addingTimeInterval(24 * 60 * 60) }
            return (now >= start && now <= end)
        }

        // RED: any illegal restriction active now
        if spot.restrictions.contains(where: { r in
            (r.type == .noParking || r.type == .streetCleaning) && isActive(r)
        }) {
            return .red
        }

        // BLUE: permit/ADA required active now
        if spot.restrictions.contains(where: { r in
            r.type == .permit && isActive(r)
        }) {
            return .blue
        }

        // PURPLE: metered/paid active now
        if spot.restrictions.contains(where: { r in
            r.type == .metered && isActive(r)
        }) {
            return .purple
        }

        // YELLOW: an illegal restriction (noParking/streetCleaning) starts within leadMinutes
        if let next = nextIllegalStart(for: spot, from: now) {
            if next.timeIntervalSince(now) <= TimeInterval(max(0, leadMinutes)) * 60 {
                return .yellow
            }
        }

        // If there are no restrictions at all, treat as unknown rather than green
        if spot.restrictions.isEmpty { return .gray }

        return .green
    }

    static func status(for scan: SignScan, now: Date = Date(), leadMinutes: Int = 15) -> ParkingSignalStatus {
        if let spot = scan.spot { return status(for: spot, now: now, leadMinutes: leadMinutes) }
        // If the scan isn't attached to a spot or is incomplete, treat as unknown
        if scan.status != "complete" { return .gray }
        // Without attached restrictions, we cannot reliably compute; remain gray
        return .gray
    }

    // Evaluate from an AIAnalysisResponse (pre‑save preview)
    static func status(for analysis: AIAnalysisResponse, now: Date = Date(), leadMinutes: Int = 15) -> ParkingSignalStatus {
        let cal = Calendar.current
        let weekday0_6 = (cal.component(.weekday, from: now) + 6) % 7

        func parseHHmm(_ s: String) -> (Int, Int)? {
            let parts = s.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
            return (h, m)
        }
        func todayAt(_ h: Int, _ m: Int, ref: Date) -> Date {
            var c = Calendar.current.dateComponents([.year, .month, .day], from: ref)
            c.hour = h; c.minute = m; c.second = 0
            return Calendar.current.date(from: c) ?? ref
        }
        func isActive(_ r: AIRestriction) -> Bool {
            if !r.daysOfWeek.isEmpty && !r.daysOfWeek.contains(weekday0_6) { return false }
            // Duration-only restrictions are treated as active now if durationMinutes > 0 (time-limited parking)
            if let dur = r.durationMinutes, dur > 0 { return true }
            guard let s = parseHHmm(r.startTime), let e = parseHHmm(r.endTime) else { return false }
            var start = todayAt(s.0, s.1, ref: now)
            var end = todayAt(e.0, e.1, ref: now)
            if end <= start { end = end.addingTimeInterval(24 * 60 * 60) }
            return (now >= start && now <= end)
        }

        // RED
        if analysis.restrictions.contains(where: { r in (r.type == .no_parking || r.type == .street_cleaning) && isActive(r) }) {
            return .red
        }
        // BLUE
        if analysis.restrictions.contains(where: { $0.type == .permit && isActive($0) }) { return .blue }
        // PURPLE
        if analysis.restrictions.contains(where: { $0.type == .metered && isActive($0) }) { return .purple }

        // YELLOW: next illegal start within leadMinutes
        if let next = nextIllegalStart(for: analysis, from: now) {
            if next.timeIntervalSince(now) <= TimeInterval(max(0, leadMinutes)) * 60 {
                return .yellow
            }
        }

        if analysis.restrictions.isEmpty { return .gray }
        return .green
    }

    // MARK: - Helpers

    private static func nextIllegalStart(for spot: ParkingSpot, from now: Date) -> Date? {
        let cal = Calendar.current
        func weekdayIndex0_6(_ date: Date) -> Int { (cal.component(.weekday, from: date) + 6) % 7 }
        func hourMinute(_ date: Date) -> (Int, Int) { (cal.component(.hour, from: date), cal.component(.minute, from: date)) }
        var best: Date? = nil
        for r in spot.restrictions where (r.type == .noParking || r.type == .streetCleaning) {
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
        return best
    }

    private static func nextIllegalStart(for analysis: AIAnalysisResponse, from now: Date) -> Date? {
        let cal = Calendar.current
        func weekdayIndex0_6(_ date: Date) -> Int { (cal.component(.weekday, from: date) + 6) % 7 }
        func parseHHmm(_ s: String) -> (Int, Int)? {
            let parts = s.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
            return (h, m)
        }
        var best: Date? = nil
        for r in analysis.restrictions where (r.type == .no_parking || r.type == .street_cleaning) {
            let days = r.daysOfWeek
            if days.isEmpty { continue }
            guard let (h, m) = parseHHmm(r.startTime) else { continue }
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
        return best
    }

    private static func todayAt(hour: Int, minute: Int, ref: Date) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: ref)
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return Calendar.current.date(from: comps) ?? ref
    }
}
