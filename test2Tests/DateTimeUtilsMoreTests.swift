#if canImport(Testing)
import Foundation
import Testing
@testable import ParkSignal_AI

/// Additional coverage for the pure date/time helpers, using a fixed UTC
/// gregorian calendar so every assertion is exact and timezone-independent.
@Suite("DateTimeUtils — more")
struct DateTimeUtilsMoreTests {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    // MARK: - weekdayIndex0_6

    @Test("weekdayIndex0_6 maps Sunday=0 … Saturday=6")
    func weekdayIndexMapping() {
        // 2024-01-07 is a Sunday; 2024-01-08 Monday; 2024-01-13 Saturday.
        #expect(DateTimeUtils.weekdayIndex0_6(iso("2024-01-07T12:00:00Z"), calendar: utc) == 0)
        #expect(DateTimeUtils.weekdayIndex0_6(iso("2024-01-08T12:00:00Z"), calendar: utc) == 1)
        #expect(DateTimeUtils.weekdayIndex0_6(iso("2024-01-13T12:00:00Z"), calendar: utc) == 6)
    }

    // MARK: - parseHHmm boundaries

    @Test("parseHHmm accepts range boundaries and rejects overflow")
    func parseHHmmBoundaries() {
        #expect(DateTimeUtils.parseHHmm("00:00")?.hour == 0)
        #expect(DateTimeUtils.parseHHmm("23:59")?.minute == 59)
        #expect(DateTimeUtils.parseHHmm("24:00") == nil)
        #expect(DateTimeUtils.parseHHmm("-1:00") == nil)
        #expect(DateTimeUtils.parseHHmm("09:60") == nil)
        #expect(DateTimeUtils.parseHHmm("09-30") == nil)
    }

    // MARK: - nextOccurrence

    @Test("nextOccurrence returns the exact next matching day/time")
    func nextOccurrenceExact() {
        // From Monday 2024-01-01 12:00, next Tuesday 09:00 is 2024-01-02 09:00.
        let now = iso("2024-01-01T12:00:00Z")
        let next = DateTimeUtils.nextOccurrence(daysOfWeek: [2], hour: 9, minute: 0,
                                                from: now, calendar: utc, lookaheadDays: 7)
        #expect(next == iso("2024-01-02T09:00:00Z"))
    }

    @Test("nextOccurrence with empty days is nil")
    func nextOccurrenceEmpty() {
        let now = iso("2024-01-01T12:00:00Z")
        #expect(DateTimeUtils.nextOccurrence(daysOfWeek: [], hour: 9, minute: 0,
                                             from: now, calendar: utc) == nil)
    }

    @Test("nextOccurrence returns nil when no match within lookahead")
    func nextOccurrenceOutOfWindow() {
        // Monday; ask only for Saturday (day 6) with a 0-day lookahead → nothing.
        let now = iso("2024-01-01T12:00:00Z")
        #expect(DateTimeUtils.nextOccurrence(daysOfWeek: [6], hour: 9, minute: 0,
                                             from: now, calendar: utc, lookaheadDays: 0) == nil)
    }

    @Test("nextOccurrence skips a same-day time that already passed")
    func nextOccurrenceSameDayPast() {
        // Monday 12:00; Monday 09:00 already passed → next Monday next week.
        let now = iso("2024-01-01T12:00:00Z")
        let next = DateTimeUtils.nextOccurrence(daysOfWeek: [1], hour: 9, minute: 0,
                                                from: now, calendar: utc, lookaheadDays: 14)
        #expect(next == iso("2024-01-08T09:00:00Z"))
    }

    // MARK: - countdownString

    @Test("countdownString formats days, hours, minutes and 'now'")
    func countdownFormatting() {
        let base = iso("2024-01-01T00:00:00Z")
        #expect(DateTimeUtils.countdownString(to: base.addingTimeInterval(90 * 60), from: base) == "1h 30m")
        #expect(DateTimeUtils.countdownString(to: base.addingTimeInterval(5 * 60 + 10), from: base) == "5m 10s")
        #expect(DateTimeUtils.countdownString(to: base.addingTimeInterval(2 * 86_400), from: base) == "2d")
        #expect(DateTimeUtils.countdownString(to: base, from: base) == "now")
        #expect(DateTimeUtils.countdownString(to: base.addingTimeInterval(-60), from: base) == "now")
    }

    // MARK: - timeWindowDescription overnight

    @Test("timeWindowDescription rolls an overnight end past midnight")
    func timeWindowOvernightDiffers() {
        let ref = iso("2024-01-01T00:00:00Z")
        let start = DateTimeUtils.todayAt(hour: 22, minute: 0, ref: ref, calendar: utc)
        let end = DateTimeUtils.todayAt(hour: 6, minute: 0, ref: ref, calendar: utc)
        let s = DateTimeUtils.timeWindowDescription(start: start, end: end, calendar: utc)
        // Contains a separator and two distinct endpoints.
        #expect(s.contains(" - "))
        let parts = s.components(separatedBy: " - ")
        #expect(parts.count == 2)
        #expect(parts[0] != parts[1])
    }
}
#endif
