#if canImport(Testing)
import Foundation
import Testing
@testable import ParkSignal_AI

/// Additional edge cases for the on-device parser, complementing
/// `ParkingTextParserTests`.
@Suite("ParkingTextParser — more")
struct ParkingTextParserMoreTests {
    private let parser = ParkingTextParser()

    private func first(_ text: String) -> AIRestriction? {
        parser.analyze(ocrText: text).restrictions.first
    }

    @Test("'DAILY' expands to all seven days")
    func dailyAllDays() {
        let r = first("NO PARKING 8AM-10AM DAILY")
        #expect(r?.type == .no_parking)
        #expect(r?.daysOfWeek == [0, 1, 2, 3, 4, 5, 6])
    }

    @Test("24-hour clock window is parsed")
    func twentyFourHourWindow() {
        let r = first("NO PARKING 22:00-06:00")
        #expect(r?.type == .no_parking)
        #expect(r?.startTime == "22:00")
        #expect(r?.endTime == "06:00")
    }

    @Test("Minutes inside the window are preserved")
    func minutesInWindow() {
        let r = first("NO PARKING 8:30AM-10:00AM")
        #expect(r?.startTime == "08:30")
        #expect(r?.endTime == "10:00")
    }

    @Test("Wrap-around day range Sat–Mon → [0,1,6]")
    func wrapAroundDayRange() {
        let r = first("NO PARKING SAT-MON 8AM-10AM")
        #expect(r?.type == .no_parking)
        #expect(r?.daysOfWeek == [0, 1, 6])
    }

    @Test("'STREET SWEEPING' maps to street cleaning")
    func streetSweeping() {
        let r = first("STREET SWEEPING WED 9AM-11AM")
        #expect(r?.type == .street_cleaning)
        #expect(r?.daysOfWeek == [3])
    }

    @Test("'NO STOPPING' maps to no parking with a PM window")
    func noStopping() {
        let r = first("NO STOPPING 4PM-6PM")
        #expect(r?.type == .no_parking)
        #expect(r?.startTime == "16:00")
        #expect(r?.endTime == "18:00")
    }

    @Test("Duration with no space ('3HR PARKING') is metered with minutes")
    func durationNoSpace() {
        let r = first("3HR PARKING")
        #expect(r?.type == .metered)
        #expect(r?.durationMinutes == 180)
    }

    @Test("Multi-line text yields one restriction per recognizable line")
    func multiLine() {
        let result = parser.analyze(ocrText: "NO PARKING 8AM-10AM MON\nSTREET CLEANING TUE 9AM-11AM")
        #expect(result.restrictions.count == 2)
        #expect(result.restrictions.map(\.type) == [.no_parking, .street_cleaning])
    }

    @Test("A bare time window with no parking context is not a rule")
    func bareWindowIgnored() {
        #expect(parser.analyze(ocrText: "8AM-10AM").restrictions.isEmpty)
    }
}
#endif
