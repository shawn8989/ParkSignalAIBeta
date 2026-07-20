// ParkingTextParser.swift
import Foundation

struct ParkingTextParser {

    func analyze(ocrText: String) -> AIAnalysisResponse {
        var results: [AIRestriction] = []
        let lines = ocrText
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for line in lines {
            // Try explicit window first
            if let times = extractTimeRange(from: line), let type = detectType(in: line) ?? (line.lowercased().contains("hour") ? .metered : nil) {
                let days = extractDays(from: line)
                let r = AIRestriction(
                    type: type,
                    daysOfWeek: days.isEmpty ? defaultDays(for: type) : days,
                    startTime: times.start,
                    endTime: times.end,
                    notes: line,
                    durationMinutes: nil
                )
                results.append(r)
                continue
            }

            // Try duration pattern like "3 HOUR PARKING", "2 HOURS", "90 MINUTES"
            if let duration = extractDuration(from: line) {
                let type: AIRestrictionType = detectType(in: line) ?? .metered
                let days = extractDays(from: line)
                let r = AIRestriction(
                    type: type,
                    daysOfWeek: days.isEmpty ? defaultDays(for: type) : days,
                    startTime: "00:00",
                    endTime: "00:00",
                    notes: line,
                    durationMinutes: duration
                )
                results.append(r)
                continue
            }
        }

        // Fallback: try whole text once
        if results.isEmpty {
            let type = detectType(in: ocrText) ?? .other
            let days = extractDays(from: ocrText)
            if let times = extractTimeRange(from: ocrText) {
                let r = AIRestriction(
                    type: type,
                    daysOfWeek: days.isEmpty ? defaultDays(for: type) : days,
                    startTime: times.start,
                    endTime: times.end,
                    notes: nil,
                    durationMinutes: nil
                )
                results.append(r)
            } else if let dur = extractDuration(from: ocrText) {
                let r = AIRestriction(
                    type: type == .other ? .metered : type,
                    daysOfWeek: days.isEmpty ? defaultDays(for: type) : days,
                    startTime: "00:00",
                    endTime: "00:00",
                    notes: nil,
                    durationMinutes: dur
                )
                results.append(r)
            }
        }

        return AIAnalysisResponse(restrictions: results)
    }

    // MARK: - Heuristics

    private func detectType(in s: String) -> AIRestrictionType? {
        let l = s.lowercased()
        if l.contains("street") && (l.contains("clean") || l.contains("sweep")) { return .street_cleaning }
        if l.contains("no parking") || l.contains("tow away") { return .no_parking }
        if l.contains("meter") { return .metered }
        if l.contains("permit") { return .permit }
        if l.contains("parking") { return .other }
        return nil
    }

    private func extractDays(from s: String) -> [Int] {
        let l = s.lowercased()
        var days = Set<Int>()

        if l.contains("daily") || l.contains("every day") || l.contains("everyday") {
            return Array(0...6)
        }

        // Ranges like Mon-Fri, Tue–Thu, Wed to Fri
        if let range = l.range(of: #"(sun|mon|tue|tues|wed|weds|thu|thur|thurs|fri|sat)\s*(?:-|–|to)\s*(sun|mon|tue|tues|wed|weds|thu|thur|thurs|fri|sat)"#, options: .regularExpression) {
            let substr = String(l[range])
            let tokens = substr
                .replacingOccurrences(of: "to", with: "-")
                .replacingOccurrences(of: "–", with: "-")
                .split(separator: "-")
                .map { String($0) }
            if tokens.count == 2, let sIdx = dayIndex(tokens[0]), let eIdx = dayIndex(tokens[1]) {
                var i = sIdx
                while true {
                    days.insert(i)
                    if i == eIdx { break }
                    i = (i + 1) % 7
                    if days.count > 7 { break }
                }
            }
        }

        // Individual mentions
        for (key, idx) in dayTokens {
            if l.contains(key) { days.insert(idx) }
        }

        return Array(days).sorted()
    }

    private func dayIndex(_ token: String) -> Int? {
        switch token {
        case "sun","sunday": return 0
        case "mon","monday": return 1
        case "tue","tues","tuesday": return 2
        case "wed","weds","wednesday": return 3
        case "thu","thur","thurs","thursday": return 4
        case "fri","friday": return 5
        case "sat","saturday": return 6
        default: return nil
        }
    }

    private let dayTokens: [(String, Int)] = [
        ("sunday",0),("sun",0),
        ("monday",1),("mon",1),
        ("tuesday",2),("tues",2),("tue",2),
        ("wednesday",3),("weds",3),("wed",3),
        ("thursday",4),("thurs",4),("thur",4),("thu",4),
        ("friday",5),("fri",5),
        ("saturday",6),("sat",6)
    ]

    private func extractTimeRange(from s: String) -> (start: String, end: String)? {
        // Matches "8AM", "8:30 AM", "22:00", etc. We take the first two times.
        let pattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let l = s.lowercased()
        let matches = regex.matches(in: l, range: NSRange(l.startIndex..., in: l))
        guard matches.count >= 2 else { return nil }

        func time(_ m: NSTextCheckingResult) -> (h: Int, m: Int, mer: String?)? {
            guard let hrR = Range(m.range(at: 1), in: l) else { return nil }
            let h = Int(l[hrR]) ?? 0
            var mm = 0
            if let mr = Range(m.range(at: 2), in: l) { mm = Int(l[mr]) ?? 0 }
            var mer: String?
            if let rr = Range(m.range(at: 3), in: l), !rr.isEmpty { mer = String(l[rr]) }
            return (h, mm, mer)
        }

        guard let t1 = time(matches[0]), let t2 = time(matches[1]) else { return nil }
        let start = to24h(hour: t1.h, minute: t1.m, meridiem: t1.mer)
        // If second meridiem missing, assume same as first
        let end = to24h(hour: t2.h, minute: t2.m, meridiem: t2.mer ?? t1.mer)
        return (start, end)
    }

    private func to24h(hour: Int, minute: Int, meridiem: String?) -> String {
        var h = hour % 24
        let m = minute % 60
        if let mer = meridiem?.lowercased() {
            if mer == "am" { if h == 12 { h = 0 } }
            if mer == "pm" { if h != 12 { h += 12 } }
        }
        return String(format: "%02d:%02d", h, m)
    }

    private func defaultDays(for type: AIRestrictionType) -> [Int] {
        switch type {
        case .street_cleaning:
            // Usually a specific weekday; leave empty so user confirms
            return []
        default:
            // Reasonable default when days not specified
            return Array(0...6)
        }
    }

    private func extractDuration(from s: String) -> Int? {
        let l = s.lowercased()
        // Matches "3 hour", "3 hr", "3hrs", "90 min", "90 minutes"
        let patterns = [
            #"(\d{1,3})\s*(hour|hr|hrs|hours)"#,
            #"(\d{1,3})\s*(min|mins|minute|minutes)"#
        ]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: .caseInsensitive) {
                if let m = regex.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)),
                   let r = Range(m.range(at: 1), in: l),
                   let n = Int(l[r]) {
                    if p.contains("hour") || p.contains("hr") { return n * 60 }
                    return n
                }
            }
        }
        return nil
    }
}
