// ParkingTextParser.swift
import Foundation

/// On-device weekly-rule parser. Unsupported conditions retain their original
/// text and require manual review; no network service is used by v1.
struct ParkingTextParser {

    func analyze(ocrText: String) -> AIAnalysisResponse {
        let lines = ocrText.replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return AIAnalysisResponse(restrictions: []) }
        let independent = lines.filter { detectType(in: $0) != nil && !extractTimeWindows(from: $0).isEmpty }
        let rules: [AIRestriction]
        if independent.count >= 2 {
            let shared = lines.filter { !independent.contains($0) }.joined(separator: " ")
            rules = independent.flatMap { restrictions(from: $0 + " " + shared) }
        } else {
            rules = restrictions(from: lines.joined(separator: " "))
        }
        return AIAnalysisResponse(restrictions: rules)
    }

    private func restrictions(from text: String) -> [AIRestriction] {
        let duration = extractDuration(from: text)
        guard let type = detectType(in: text) ?? (duration != nil ? .time_limited : nil) else { return [] }
        let windows = extractTimeWindows(from: text)
        let dayInfo = extractDays(from: text)
        var reasons = unsupportedReasons(in: text)
        if dayInfo.lowConfidence { reasons.append("The weekday exception needs manual review.") }
        if type == .other { reasons.append("The restriction type is unclear.") }
        if type == .street_cleaning && dayInfo.days.isEmpty { reasons.append("Confirm the street-cleaning days.") }
        if windows.isEmpty && text.range(of: #"\b\d{1,2}\s*(?::\d{2}|am|pm)\b"#, options: .caseInsensitive.union(.regularExpression)) != nil {
            reasons.append("A complete time window could not be read.")
        }
        if text.range(of: #"\b\d{1,2}\s*[-–]\s*\d{1,2}\b(?!\s*(?:am|pm|:))"#, options: .caseInsensitive.union(.regularExpression)) != nil {
            reasons.append("Confirm AM/PM for the printed hours.")
        }
        if duration != nil && (type == .no_parking || type == .street_cleaning) {
            reasons.append("A time limit is combined with a blocking or loading rule. Review each condition.")
        }
        let lower = text.lowercased()
        if (type != .permit && lower.contains("permit") && !lower.contains("except")) ||
            ((type == .no_parking || type == .street_cleaning) && (lower.contains("meter") || lower.contains("pay to park"))) {
            reasons.append("Multiple rule types need separate manual review.")
        }
        let days = dayInfo.days.isEmpty ? Array(0...6) : dayInfo.days
        let ranges = windows.isEmpty ? [(start: "00:00", end: "00:00")] : windows
        return ranges.map { window in
            AIRestriction(type: type, daysOfWeek: days, startTime: window.start, endTime: window.end,
                          notes: text, durationMinutes: duration,
                          exceptHolidays: dayInfo.exceptHolidays ? true : nil,
                          needsReview: !reasons.isEmpty, reviewReasons: reasons)
        }
    }

    /// These rules require information our weekly schedule cannot represent. Keep
    /// the original text and make them non-actionable rather than guessing.
    private func unsupportedReasons(in text: String) -> [String] {
        let l = text.lowercased()
        var result: [String] = []
        let checks: [(String, String)] = [
            (#"\b(?:\d+(?:st|nd|rd|th)|first|second|third|fourth|fifth|last)\b"#, "Monthly schedules need manual review."),
            (#"\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?|winter|summer|seasonal|snow)\b"#, "Seasonal or date-specific rules need manual review."),
            (#"\b(?:holidays?|school days?|school hours|event|game days?)\b"#, "Holiday, school or event rules need manual review."),
            (#"\b(?:except|excluding|excepting)\s+(?:vehicles?|trucks?|buses|residents?|permit|with|commercial)\b"#, "Vehicle or permit exemptions need manual review."),
            (#"\b(?:loading|unloading|passenger|commercial|exempt|exempted|authorized vehicles)\b"#, "Loading and vehicle-specific rules need manual review."),
            (#"\b(?:after|before|until)\s+\d"#, "Open-ended hours need manual review.")
        ]
        for (pattern, reason) in checks where l.range(of: pattern, options: .regularExpression) != nil { result.append(reason) }
        return result
    }

    private func detectType(in text: String) -> AIRestrictionType? {
        let l = text.lowercased()
        // Permit exemptions must not turn general parking into permit-only parking.
        let base = l.components(separatedBy: "except").first ?? l
        if (l.contains("street") && (l.contains("clean") || l.contains("sweep"))) || l.contains("sweeping") || l.contains("sanitation") { return .street_cleaning }
        if base.contains("no parking") || base.contains("no stopping") || base.contains("no standing") || base.contains("tow") || base.contains("bus stop") || base.contains("hydrant") || base.contains("fire lane") || base.contains("loading") { return .no_parking }
        if base.contains("permit") || base.contains("resident") || base.contains("ada") || base.contains("handicap") || base.contains("disabled") || base.contains("wheelchair") { return .permit }
        if base.contains("meter") || base.contains("pay to park") || base.contains("pay-to-park") || base.contains("paid parking") { return .metered }
        if extractDuration(from: base) != nil { return .time_limited }
        if base.contains("parking") { return .other }
        return nil
    }

    private struct DayInfo {
        var days: [Int]
        var exceptHolidays: Bool
        var lowConfidence: Bool
    }

    private func extractDays(from text: String) -> DayInfo {
        let l = text.lowercased()
        // Match only a contiguous day/holiday phrase, not arbitrary words before
        // "excepted" or the remaining sign after "except trucks".
        let day = #"(?:sundays?|sun|mondays?|mon|tuesdays?|tues?|wednesdays?|weds?|thursdays?|thurs?|thur|fridays?|fri|saturdays?|sat|weekends?|weekdays?|holidays?)"#
        let phrase = day + #"(?:(?:\s*(?:and|&|,|[-–]|to|thru|through)\s*|\s+)"# + day + #")*"#
        let pattern = #"\b(?:except|excluding|excepting)\s+("# + phrase + #")\b|\b("# + phrase + #")\s+(?:excepted|excluded)\b"#
        var includeText = l
        var excluded = Set<Int>()
        var holidays = false
        var found = false
        if let re = try? NSRegularExpression(pattern: pattern) {
            let ns = l as NSString
            for m in re.matches(in: l, range: NSRange(location: 0, length: ns.length)).reversed() {
                let range = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
                let part = ns.substring(with: range)
                excluded.formUnion(daySet(in: part))
                holidays = holidays || part.contains("holiday")
                found = true
                if let r = Range(m.range, in: includeText) { includeText.replaceSubrange(r, with: " ") }
            }
        }
        var included = daySet(in: includeText)
        if included.isEmpty { included = Set(0...6) }
        let active = included.subtracting(excluded)
        return DayInfo(days: active.sorted(), exceptHolidays: holidays,
                       lowConfidence: found && active.isEmpty)
    }

    private func daySet(in seg: String) -> Set<Int> {
        if seg.range(of: #"\b(daily|everyday|every day|all days|7 days|24/7)\b"#, options: .regularExpression) != nil {
            return Set(0...6)
        }
        var days = Set<Int>()
        if seg.contains("weekend") { days.formUnion([0, 6]) }
        if seg.contains("weekday") { days.formUnion([1, 2, 3, 4, 5]) }

        // Ranges: MON-FRI, MON THRU FRI, TUE–THU, WED TO FRI (with wrap-around).
        let rangePat = #"(sun|mon|tue|tues|wed|weds|thu|thur|thurs|fri|sat)[a-z]*\s*(?:-|–|to|thru|through|til|until)\s*(sun|mon|tue|tues|wed|weds|thu|thur|thurs|fri|sat)[a-z]*"#
        if let re = try? NSRegularExpression(pattern: rangePat, options: .caseInsensitive) {
            let ns = seg as NSString
            for m in re.matches(in: seg, range: NSRange(location: 0, length: ns.length)) {
                guard let s = dayIndex(ns.substring(with: m.range(at: 1))),
                      let e = dayIndex(ns.substring(with: m.range(at: 2))) else { continue }
                var i = s
                var guardCount = 0
                while true {
                    days.insert(i)
                    if i == e { break }
                    i = (i + 1) % 7
                    guardCount += 1; if guardCount > 7 { break }
                }
            }
        }

        // Individual mentions. Strip range separator words first so "thru" isn't
        // mistaken for "thu" (Thursday).
        let indiv = seg.replacingOccurrences(of: #"\b(thru|through|until|til)\b"#, with: " ", options: .regularExpression)
        for (key, idx) in dayTokens where indiv.range(of: "\\b" + key + "s?\\b", options: .regularExpression) != nil { days.insert(idx) }
        return days
    }

    private func dayIndex(_ token: String) -> Int? {
        switch token.lowercased() {
        case "sun", "sunday": return 0
        case "mon", "monday": return 1
        case "tue", "tues", "tuesday": return 2
        case "wed", "weds", "wednesday": return 3
        case "thu", "thur", "thurs", "thursday": return 4
        case "fri", "friday": return 5
        case "sat", "saturday": return 6
        default: return nil
        }
    }

    private let dayTokens: [(String, Int)] = [
        ("sunday", 0), ("sun", 0),
        ("monday", 1), ("mon", 1),
        ("tuesday", 2), ("tues", 2), ("tue", 2),
        ("wednesday", 3), ("weds", 3), ("wed", 3),
        ("thursday", 4), ("thurs", 4), ("thur", 4), ("thu", 4),
        ("friday", 5), ("fri", 5),
        ("saturday", 6), ("sat", 6),
    ]

    // MARK: - Time windows (supports multiple)

    private func extractTimeWindows(from text: String) -> [(start: String, end: String)] {
        var l = text.lowercased().replacingOccurrences(of: "a.m.", with: "am").replacingOccurrences(of: "p.m.", with: "pm")
        l = l.replacingOccurrences(of: #"\b(?:12\s*)?noon\b"#, with: "12pm", options: .regularExpression)
        l = l.replacingOccurrences(of: #"\b(?:12\s*)?midnight\b"#, with: "12am", options: .regularExpression)
        // Strip durations and ordinal dates; a window must have an explicit separator.
        l = l.replacingOccurrences(of: #"\b\d{1,3}\s*(?:hours?|hrs?|mins?|minutes?)\b|\b\d+(?:st|nd|rd|th)\b"#, with: " ", options: .regularExpression)
        let token = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        let pattern = #"(?<![\d:])"# + token + #"\s*(?:-|–|—|to)\s*"# + token + #"(?![\d:])"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = l as NSString
        return re.matches(in: l, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            func value(_ n: Int) -> String? { m.range(at: n).location == NSNotFound ? nil : ns.substring(with: m.range(at: n)) }
            guard let h1 = Int(value(1) ?? ""), let h2 = Int(value(4) ?? ""), h1 < 24, h2 < 24 else { return nil }
            let m1 = Int(value(2) ?? "0") ?? -1, m2 = Int(value(5) ?? "0") ?? -1
            guard (0..<60).contains(m1), (0..<60).contains(m2) else { return nil }
            var a = value(3), b = value(6)
            if (a != nil && !(1...12).contains(h1)) || (b != nil && !(1...12).contains(h2)) { return nil }
            if a == nil, let end = b, h1 <= 12 {
                a = end
                if minutes(hour: h1, minute: m1, meridiem: a) > minutes(hour: h2, minute: m2, meridiem: b) {
                    a = end == "pm" ? "am" : "pm"
                }
            } else if b == nil, let start = a, h2 <= 12 {
                b = start
                if minutes(hour: h2, minute: m2, meridiem: b) <= minutes(hour: h1, minute: m1, meridiem: a) {
                    b = start == "am" ? "pm" : "am"
                }
            } else if a == nil, b == nil, h1 <= 12, h2 <= 12, h2 < h1 {
                a = "am"; b = "pm" // explicitly review-required when both suffixes are absent
            }
            return (format(minutes(hour: h1, minute: m1, meridiem: a)), format(minutes(hour: h2, minute: m2, meridiem: b)))
        }
    }

    private func minutes(hour: Int, minute: Int, meridiem: String?) -> Int {
        let h = meridiem == nil ? hour : (hour % 12 + (meridiem == "pm" ? 12 : 0))
        return h * 60 + minute
    }

    private func format(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    // MARK: - Duration (digits and spelled-out)
    // Permit-zone text (e.g. "Zone A") is preserved verbatim in each restriction's
    // `notes`, so no separate extraction is needed here.

    private func extractDuration(from s: String) -> Int? {
        let l = s.lowercased()
        if l.range(of: #"(1/2|half)\s*(hour|hr)"#, options: .regularExpression) != nil { return 30 }
        if let re = try? NSRegularExpression(pattern: #"(\d{1,3})\s*(hours?|hrs?)"#, options: .caseInsensitive),
           let m = re.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)),
           let r = Range(m.range(at: 1), in: l), let n = Int(l[r]) {
            return n * 60
        }
        if let re = try? NSRegularExpression(pattern: #"(\d{1,3})\s*(mins?|minutes?)"#, options: .caseInsensitive),
           let m = re.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)),
           let r = Range(m.range(at: 1), in: l), let n = Int(l[r]) {
            return n
        }
        let spelled: [(String, Int)] = [("one", 1), ("two", 2), ("three", 3), ("four", 4),
                                        ("five", 5), ("six", 6), ("eight", 8), ("ten", 10),
                                        ("twelve", 12)]
        for (w, v) in spelled where l.range(of: #"\b\#(w)\s*(hours?|hrs?)"#, options: .regularExpression) != nil {
            return v * 60
        }
        return nil
    }
}
