#if canImport(Testing)
import Foundation
import Testing
@testable import ParkSignal_AI

@Suite("DateTimeUtils tests")
struct DateTimeUtilsTests {
    @Test("parseHHmm valid")
    func parseHHmmValid() async throws {
        let v = DateTimeUtils.parseHHmm("09:30")
        #expect(v?.hour == 9 && v?.minute == 30)
    }

    @Test("parseHHmm invalid")
    func parseHHmmInvalid() async throws {
        #expect(DateTimeUtils.parseHHmm("") == nil)
        #expect(DateTimeUtils.parseHHmm("25:00") == nil)
        #expect(DateTimeUtils.parseHHmm("12:60") == nil)
        #expect(DateTimeUtils.parseHHmm("abc") == nil)
    }

    @Test("todayAt constructs same-day time")
    func todayAtConstructs() async throws {
        let now = ISO8601DateFormatter().date(from: "2024-01-01T12:00:00Z")!
        let cal = Calendar(identifier: .gregorian)
        let d = DateTimeUtils.todayAt(hour: 8, minute: 15, ref: now, calendar: cal)
        let h = cal.component(.hour, from: d)
        let m = cal.component(.minute, from: d)
        #expect(h == 8 && m == 15)
    }

    @Test("nextOccurrence strictly future within lookahead")
    func nextOccurrenceFuture() async throws {
        let cal = Calendar(identifier: .gregorian)
        // Monday Jan 1, 2024 12:00
        let now = ISO8601DateFormatter().date(from: "2024-01-01T12:00:00Z")!
        // Next Tuesday at 09:00 should be Jan 2, 2024 09:00Z in UTC calendar
        let next = DateTimeUtils.nextOccurrence(daysOfWeek: [2], hour: 9, minute: 0, from: now, calendar: cal, lookaheadDays: 7)
        #expect(next != nil)
    }

    @Test("timeWindowDescription handles overnight")
    func timeWindowOvernight() async throws {
        let cal = Calendar(identifier: .gregorian)
        let ref = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")!
        let start = DateTimeUtils.todayAt(hour: 22, minute: 0, ref: ref, calendar: cal)
        let end = DateTimeUtils.todayAt(hour: 6, minute: 0, ref: ref, calendar: cal)
        let s = DateTimeUtils.timeWindowDescription(start: start, end: end, calendar: cal)
        #expect(s.contains("-"))
    }
}

// The target name should match your app target where DateTimeUtils is defined.
// @testable import YourAppTarget

#endif
