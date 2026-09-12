// ParkingTextParser.swift
import Foundation

/// On-device parser that turns recognized parking-sign text into structured
/// restrictions. This is the v1 engine (no cloud AI); the cloud analyzer, when
/// enabled later, produces the same `AIAnalysisResponse` shape.
struct ParkingTextParser {

    func analyze(ocrText: String) -> AIAnalysisResponse {
        var results: [AIRestriction] = []
        let lines = ocrText
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for line in lines {
            if let r = restriction(from: line) { results.append(r) }
        }

        // Fallback: try the whole text as one blob if per-line found nothing.
        if results.isEmpty, let r = restriction(from: ocrText) {
            results.append(r)
        }

        return AIAnalysisResponse(restrictions: results)
    }

    /// Build a restriction from a single line/blob, or nil if it isn't a
    /// recognizable parking rule.
    private func restriction(from text: String) -> AIRestriction? {
        let hasLimit = hasDurationWord(text)

        // 1. Explicit time window ("8AM-10AM", "9-6PM", "22:00-06:00").
        if let times = extractTimeRange(from: text) {
            // Only treat a window as a restriction if we can attach a type
            // (a bare "8-10" with no parking context is not a rule).
            if var type = detectType(in: text) ?? (hasLimit ? .metered : nil) {
                if type == .other && hasLimit { type = .metered } // "2 HR PARKING 9-6" → metered
                let days = extractDays(from: text)
                return AIRestriction(
                    type: type,
                    daysOfWeek: days.isEmpty ? defaultDays(for: type) : days,
                    startTime: times.start,
                    endTime: times.end,
                    notes: text,
                    durationMinutes: nil
                )
            }
        }

        // 2. Duration limit with no window ("2 HOUR PARKING", "90 MINUTES").
        if let duration = extractDuration(from: text) {
            let detected = detectType(in: text)
            let type: AIRestrictionType = (detected == nil || detected == .other) ? .metered : detected!
            let days = extractDays(from: text)
            return AIRestriction(
                type: type,
                daysOfWeek: days.isEmpty ? defaultDays(for: type) : days,
                startTime: "00:00",
                endTime: "00:00",
                notes: text,
                durationMinutes: duration
            )
        }

        // 3. Type-only "anytime" signs with no time/duration
        //    ("NO PARKING ANYTIME", "TOW AWAY", "PERMIT PARKING ONLY").
        if let type = detectType(in: text), type == .no_parking || type == .permit {
            let days = extractDays(from: text)
            return AIRestriction(
                type: type,
                daysOfWeek: days.isEmpty ? Array(0...6) : days,
                startTime: "00:00",
                endTime: "00:00",
                notes: text,
                durationMinutes: nil
            )
        }

        return nil
    }

    // MARK: - Heuristics

    private func detectType(in s: String) -> AIRestrictionType? {
        let l = s.lowercased()
        if l.contains("street") && (l.contains("clean") || l.contains("sweep")) { return .street_cleaning }
        if l.contains("no parking") || l.contains("tow away") || l.contains("tow-away")
            || l.contains("no stopping") || l.contains("no standing") { return .no_parking }
        if l.contains("meter") { return .metered }
        if l.contains("permit") { return .permit }
        if l.contains("parking") { return .other }
        return nil
    }

    /// True if the text contains a duration limit like "2 HR" / "90 min".
    private func hasDurationWord(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.range(of: #"\d{1,3}\s*(hours?|hrs?|mins?|minutes?)\b"#, options: .regularExpression) != nil
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
        // Remove duration expressions first ("2 HR", "90 MIN") so their leading
        // number isn't mistaken for the start of the time window.
        let l = s.lowercased()
            .replacingOccurrences(of: #"\d{1,3}\s*(hours?|hrs?|mins?|minutes?)\b"#, with: " ", options: .regularExpression)
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

        let endMer = t2.mer ?? t1.mer
        // Infer the start meridiem from the end when the start lacks one
        // ("8-10PM" → 20:00–22:00), but only if it keeps start <= end so
        // "11-2PM" stays 11:00–14:00.
        var startMer = t1.mer
        if startMer == nil, let em = endMer {
            let startGuess = minutes(hour: t1.h, minute: t1.m, meridiem: em)
            let endValue = minutes(hour: t2.h, minute: t2.m, meridiem: endMer)
            if startGuess <= endValue { startMer = em }
        }

        let start = to24h(hour: t1.h, minute: t1.m, meridiem: startMer)
        let end = to24h(hour: t2.h, minute: t2.m, meridiem: endMer)
        return (start, end)
    }

    private func minutes(hour: Int, minute: Int, meridiem: String?) -> Int {
        var h = hour % 24
        if let mer = meridiem?.lowercased() {
            if mer == "am", h == 12 { h = 0 }
            if mer == "pm", h != 12 { h += 12 }
        }
        return h * 60 + (minute % 60)
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
