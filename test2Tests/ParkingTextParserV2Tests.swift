#if canImport(Testing)
import Foundation
import Testing
@testable import ParkSignal_AI

/// Tests for the v2 parser: exceptions/negation, weekend/weekday macros,
/// thru/through ranges, multiple time windows, spelled-out durations, broader
/// type detection, stacked-sign handling, and the needsReview flag.
@Suite("ParkingTextParser v2")
struct ParkingTextParserV2Tests {
    private let parser = ParkingTextParser()

    private func first(_ text: String) -> AIRestriction? {
        parser.analyze(ocrText: text).restrictions.first
    }
    private func all(_ text: String) -> [AIRestriction] {
        parser.analyze(ocrText: text).restrictions
    }

    // MARK: - Exceptions / negation (the reported bug)

    @Test("'except weekends' excludes Sat/Sun → Mon–Fri (not weekends-only)")
    func exceptWeekends() {
        let r = first("No Parking 8-9AM except weekends")
        #expect(r?.type == .no_parking)
        #expect(r?.daysOfWeek == [1, 2, 3, 4, 5])
        #expect(r?.startTime == "08:00")
        #expect(r?.needsReview == true)
    }

    @Test("'except Sat Sun' → Mon–Fri")
    func exceptSatSun() {
        #expect(first("No Parking 8-9AM except Sat Sun")?.daysOfWeek == [1, 2, 3, 4, 5])
    }

    @Test("'except Sunday' → Mon–Sat")
    func exceptSunday() {
        #expect(first("No Parking 8-9AM except Sunday")?.daysOfWeek == [1, 2, 3, 4, 5, 6])
    }

    @Test("Postfix 'Sundays and Holidays Excepted' → Mon–Sat + holiday flag")
    func sundaysAndHolidaysExcepted() {
        let r = first("2 Hour Parking 8AM-6PM Sundays and Holidays Excepted")
        #expect(r?.daysOfWeek == [1, 2, 3, 4, 5, 6])
        #expect(r?.exceptHolidays == true)
        #expect(r?.type == .metered)
    }

    @Test("'Mon-Fri ... except holidays' keeps Mon–Fri and sets the holiday flag")
    func monFriExceptHolidays() {
        let r = first("2 Hour Parking 8AM-6PM Mon-Fri except holidays")
        #expect(r?.daysOfWeek == [1, 2, 3, 4, 5])
        #expect(r?.exceptHolidays == true)
    }

    // MARK: - Weekend / weekday macros

    @Test("'Weekdays' → Mon–Fri")
    func weekdaysMacro() {
        #expect(first("No Parking 8AM-6PM Weekdays")?.daysOfWeek == [1, 2, 3, 4, 5])
    }

    @Test("'Weekends' → Sat/Sun")
    func weekendsMacro() {
        #expect(first("No Parking 8AM-6PM Weekends")?.daysOfWeek == [0, 6])
    }

    // MARK: - THRU / THROUGH ranges

    @Test("'MON THRU FRI' → Mon–Fri")
    func monThruFri() {
        #expect(first("No Parking 7AM-9AM Mon Thru Fri")?.daysOfWeek == [1, 2, 3, 4, 5])
    }

    @Test("'MON THROUGH FRI' → Mon–Fri")
    func monThroughFri() {
        #expect(first("No Parking 7AM-9AM Mon Through Fri")?.daysOfWeek == [1, 2, 3, 4, 5])
    }

    // MARK: - Multiple time windows (rush hour)

    @Test("Two windows produce two restrictions")
    func rushHourTwoWindows() {
        let rs = all("No Stopping 7-9AM 4-6PM")
        #expect(rs.count == 2)
        #expect(rs.map(\.type) == [.no_parking, .no_parking])
        #expect(rs.map(\.startTime) == ["07:00", "16:00"])
        #expect(rs.map(\.endTime) == ["09:00", "18:00"])
        #expect(rs.allSatisfy { $0.needsReview == true })
    }

    // MARK: - Spelled-out durations

    @Test("'ONE HOUR PARKING' → 60 min metered")
    func spelledOneHour() {
        let r = first("One Hour Parking")
        #expect(r?.type == .metered)
        #expect(r?.durationMinutes == 60)
    }

    @Test("'TWO HOUR PARKING 9AM-6PM' → metered window, no duration")
    func spelledTwoHourWithWindow() {
        let r = first("Two Hour Parking 9AM-6PM")
        #expect(r?.type == .metered)
        #expect(r?.startTime == "09:00")
        #expect(r?.endTime == "18:00")
        #expect(r?.durationMinutes == nil)
    }

    @Test("'30 MIN' → 30 min")
    func thirtyMin() {
        #expect(first("30 Minute Parking")?.durationMinutes == 30)
    }

    // MARK: - Broader type detection

    @Test("'No Standing' maps to no parking")
    func noStanding() {
        #expect(first("No Standing 8AM-6PM")?.type == .no_parking)
    }

    @Test("'Loading Zone' maps to no parking (anytime)")
    func loadingZone() {
        let r = first("Loading Zone")
        #expect(r?.type == .no_parking)
        #expect(r?.daysOfWeek == [0, 1, 2, 3, 4, 5, 6])
    }

    @Test("'Handicap Parking' maps to permit")
    func handicap() {
        #expect(first("Handicap Parking Only")?.type == .permit)
    }

    @Test("'Bus Stop' maps to no parking")
    func busStop() {
        #expect(first("Bus Stop No Standing Anytime")?.type == .no_parking)
    }

    // MARK: - Stacked sign parsed as one unit (not fragmented)

    @Test("Stacked OCR lines combine into one correct restriction")
    func stackedSign() {
        let rs = all("NO PARKING\n8 AM - 10 AM\nTUESDAY\nSTREET CLEANING")
        #expect(rs.count == 1)
        #expect(rs.first?.type == .street_cleaning)
        #expect(rs.first?.daysOfWeek == [2])
        #expect(rs.first?.startTime == "08:00")
        #expect(rs.first?.endTime == "10:00")
    }

    @Test("A normal single-window sign is not flagged for review")
    func normalNotFlagged() {
        #expect(first("No Parking 8AM-10AM Mon")?.needsReview == nil)
    }
}
#endif
