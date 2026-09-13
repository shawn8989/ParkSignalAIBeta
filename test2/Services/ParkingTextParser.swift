// ParkingTextParser.swift
import Foundation

/// On-device parser that turns recognized parking-sign text into structured
/// restrictions (the v1 engine, no cloud AI). The cloud analyzer, when enabled,
/// produces the same `AIAnalysisResponse` shape and serves as the fallback.
///
/// v2 improvements over the original:
/// - Handles exceptions/negation ("except Sunday", "except weekends",
///   "Sundays and Holidays excepted") by SUBTRACTING excepted days instead of
///   mis-reading them as the active days.
/// - Understands "weekday(s)" / "weekend(s)" and "MON THRU/THROUGH FRI" ranges.
/// - Emits multiple restrictions for multiple time windows ("7-9AM 4-6PM").
/// - Reads spelled-out durations ("ONE HOUR PARKING").
/// - Broader type vocabulary (no stopping/standing, tow away, bus stop, loading,
///   hydrant, ADA/permit zones).
/// - Flags low-confidence parses via `needsReview` so the UI can ask the user to
///   confirm (and callers can prefer the cloud AI).
struct ParkingTextParser {

    func analyze(ocrText: String) -> AIAnalysisResponse {
        let lines = ocrText
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return AIAnalysisResponse(restrictions: []) }

        // If two or more OCR lines each independently carry BOTH a type and a
        // time/duration, treat them as separate rules. Otherwise parse the whole
        // sign as one unit so a stacked sign split across OCR lines is not
        // fragmented into a wrong "anytime" rule.
        let independent = lines.filter { hasType($0) && hasTiming($0) }
        if independent.count >= 2 {
            var out: [AIRestriction] = []
            for line in independent { out.append(contentsOf: restrictions(from: line)) }
            if !out.isEmpty { return AIAnalysisResponse(restrictions: out) }
        }

        let whole = lines.joined(separator: " ")
        return AIAnalysisResponse(restrictions: restrictions(from: whole))
    }

    // MARK: - Core assembly

    private func restrictions(from text: String) -> [AIRestriction] {
        let duration = extractDuration(from: text)
        let hasLimit = duration != nil
        let windows = extractTimeWindows(from: text)
        let dayInfo = extractDays(from: text)

        // 1. One or more explicit time windows.
        if !windows.isEmpty {
            guard var type = detectType(in: text) ?? (hasLimit ? .metered : nil) else {
                return [] // a bare window with no parking context is not a rule
            }
            if type == .other && hasLimit { type = .metered }
            let days = resolveDays(dayInfo, type: type)
            let review = shouldReview(dayInfo: dayInfo, type: type, windowCount: windows.count)
            return windows.map { w in
                AIRestriction(type: type, daysOfWeek: days,
                              startTime: w.start, endTime: w.end, notes: text,
                              durationMinutes: nil,
                              exceptHolidays: dayInfo.exceptHolidays ? true : nil,
                              needsReview: review ? true : nil)
            }
        }

        // 2. Duration limit with no window ("2 HOUR PARKING", "90 MIN").
        if let duration {
            let detected = detectType(in: text)
            let type: AIRestrictionType = (detected == nil || detected == .other) ? .metered : detected!
            let days = resolveDays(dayInfo, type: type)
            return [AIRestriction(type: type, daysOfWeek: days,
                                  startTime: "00:00", endTime: "00:00", notes: text,
                                  durationMinutes: duration,
                                  exceptHolidays: dayInfo.exceptHolidays ? true : nil,
                                  needsReview: shouldReview(dayInfo: dayInfo, type: type, windowCount: 0) ? true : nil)]
        }

        // 3. Type-only "anytime" signs ("NO PARKING ANYTIME", "TOW AWAY",
        //    "PERMIT PARKING ONLY").
        if let type = detectType(in: text), type == .no_parking || type == .permit {
            let days = (dayInfo.days.isEmpty && !dayInfo.hasExcept) ? Array(0...6) : resolveDays(dayInfo, type: type)
            return [AIRestriction(type: type, daysOfWeek: days,
                                  startTime: "00:00", endTime: "00:00", notes: text,
                                  durationMinutes: nil,
                                  exceptHolidays: dayInfo.exceptHolidays ? true : nil,
                                  needsReview: shouldReview(dayInfo: dayInfo, type: type, windowCount: 0) ? true : nil)]
        }

        return []
    }

    private func resolveDays(_ info: DayInfo, type: AIRestrictionType) -> [Int] {
        if !info.days.isEmpty { return info.days }
        if info.hasExcept { return [] } // exception consumed everything — surfaced via needsReview
        return defaultDays(for: type)
    }

    private func shouldReview(dayInfo: DayInfo, type: AIRestrictionType, windowCount: Int) -> Bool {
        dayInfo.lowConfidence || dayInfo.exceptHolidays || type == .other || windowCount > 1
    }

    private func defaultDays(for type: AIRestrictionType) -> [Int] {
        switch type {
        case .street_cleaning: return [] // usually a specific weekday; leave for the user to confirm
        default: return Array(0...6)
        }
    }

    // MARK: - Type detection

    private func detectType(in s: String) -> AIRestrictionType? {
        let l = s.lowercased()
        if (l.contains("street") && (l.contains("clean") || l.contains("sweep"))) || l.contains("sweeping") || l.contains("sanitation") {
            return .street_cleaning
        }
        if l.contains("permit") || l.contains("resident") || l.contains("ada")
            || l.contains("handicap") || l.contains("disabled") || l.contains("wheelchair") {
            return .permit
        }
        if l.contains("no parking") || l.contains("no stopping") || l.contains("no standing")
            || l.contains("tow away") || l.contains("tow-away") || l.contains("tow zone")
            || l.contains("bus stop") || l.contains("hydrant") || l.contains("fire lane")
            || l.contains("loading") || l.contains("do not") {
            return .no_parking
        }
        if l.contains("meter") || l.contains("pay to park") || l.contains("pay-to-park") || l.contains("paid parking") {
            return .metered
        }
        if l.contains("parking") { return .other }
        return nil
    }

    private func hasType(_ s: String) -> Bool { detectType(in: s) != nil }
    private func hasTiming(_ s: String) -> Bool { !extractTimeWindows(from: s).isEmpty || extractDuration(from: s) != nil }

    // MARK: - Days (with exception handling)

    private struct DayInfo {
        var days: [Int]           // final active days (empty = unspecified)
        var exceptHolidays: Bool
        var hasExcept: Bool
        var lowConfidence: Bool
    }

    private func extractDays(from s: String) -> DayInfo {
        let l = s.lowercased()
        var includeSeg = l
        var excludeSeg = ""
        var hasExcept = false

        if let r = l.range(of: #"\b(except|excluding|excepting|exc\.?|but not)\b"#, options: .regularExpression) {
            // Prefix form: "... except <days/holidays>"
            hasExcept = true
            includeSeg = String(l[l.startIndex..<r.lowerBound])
            excludeSeg = String(l[r.upperBound...])
        } else if let r = l.range(of: #"\b(excepted|excluded)\b"#, options: .regularExpression) {
            // Postfix form: "... <days/holidays> excepted"
            hasExcept = true
            let before = String(l[l.startIndex..<r.lowerBound])
            let words = before.split(separator: " ").map(String.init)
            excludeSeg = words.suffix(6).joined(separator: " ")
            includeSeg = "" // base becomes the full week; stated days here are the exception
        }

        var include = daySet(in: includeSeg)
        let ex = daySetWithHolidays(in: excludeSeg)
        if include.isEmpty && hasExcept { include = Set(0...6) }
        let active = include.subtracting(ex.days)
        return DayInfo(days: active.sorted(),
                       exceptHolidays: ex.holidays,
                       hasExcept: hasExcept,
                       lowConfidence: hasExcept || ex.holidays)
    }

    private func daySetWithHolidays(in seg: String) -> (days: Set<Int>, holidays: Bool) {
        (daySet(in: seg), seg.contains("holiday"))
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
        for (key, idx) in dayTokens where indiv.contains(key) { days.insert(idx) }
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

    private func extractTimeWindows(from s: String) -> [(start: String, end: String)] {
        var l = s.lowercased()
        // Remove number-bearing phrases that are NOT clock times.
        l = l.replacingOccurrences(of: #"\d{1,3}\s*(hours?|hrs?|mins?|minutes?)\b"#, with: " ", options: .regularExpression)
        l = l.replacingOccurrences(of: #"\b(zone|area|permit|space|spaces)\s*#?\s*\d+"#, with: " ", options: .regularExpression)
        l = l.replacingOccurrences(of: #"#\s*\d+"#, with: " ", options: .regularExpression)
        l = l.replacingOccurrences(of: #"\b\d+(st|nd|rd|th)\b"#, with: " ", options: .regularExpression)

        let pattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let ns = l as NSString
        struct T { let h: Int; let m: Int; let mer: String? }
        var times: [T] = []
        for mt in re.matches(in: l, range: NSRange(location: 0, length: ns.length)) {
            guard mt.range(at: 1).location != NSNotFound else { continue }
            guard let h = Int(ns.substring(with: mt.range(at: 1))), h >= 0, h <= 23 else { continue }
            var mm = 0
            if mt.range(at: 2).location != NSNotFound { mm = Int(ns.substring(with: mt.range(at: 2))) ?? 0 }
            var mer: String? = nil
            if mt.range(at: 3).location != NSNotFound {
                let x = ns.substring(with: mt.range(at: 3))
                if !x.isEmpty { mer = x }
            }
            times.append(T(h: h, m: mm, mer: mer))
        }

        var windows: [(start: String, end: String)] = []
        var i = 0
        while i + 1 < times.count {
            let t1 = times[i], t2 = times[i + 1]
            let endMer = t2.mer ?? t1.mer
            var startMer = t1.mer
            if startMer == nil, let em = endMer {
                let startGuess = minutes(hour: t1.h, minute: t1.m, meridiem: em)
                let endValue = minutes(hour: t2.h, minute: t2.m, meridiem: endMer)
                if startGuess <= endValue { startMer = em }
            }
            windows.append((to24h(hour: t1.h, minute: t1.m, meridiem: startMer),
                            to24h(hour: t2.h, minute: t2.m, meridiem: endMer)))
            i += 2
        }
        return windows
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
