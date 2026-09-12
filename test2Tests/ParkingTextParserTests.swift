#if canImport(Testing)
import Foundation
import Testing
@testable import ParkSignal_AI

@Suite("ParkingTextParser")
struct ParkingTextParserTests {
    private let parser = ParkingTextParser()

    private func first(_ text: String) -> AIRestriction? {
        parser.analyze(ocrText: text).restrictions.first
    }

    // MARK: - Time windows

    @Test("Street cleaning with a window and a single day")
    func streetCleaningWindow() {
        let r = first("No Parking 8AM-10AM Tue Street Cleaning")
        #expect(r?.type == .street_cleaning)
        #expect(r?.daysOfWeek == [2])
        #expect(r?.startTime == "08:00")
        #expect(r?.endTime == "10:00")
        #expect(r?.durationMinutes == nil)
    }

    @Test("Street cleaning stated day-first")
    func streetCleaningDayFirst() {
        let r = first("STREET CLEANING WED 8AM-10AM")
        #expect(r?.type == .street_cleaning)
        #expect(r?.daysOfWeek == [3])
        #expect(r?.startTime == "08:00")
        #expect(r?.endTime == "10:00")
    }

    @Test("No Parking with a Mon-Fri range")
    func noParkingWeekdayRange() {
        let r = first("NO PARKING MON-FRI 7AM-9AM")
        #expect(r?.type == .no_parking)
        #expect(r?.daysOfWeek == [1, 2, 3, 4, 5])
        #expect(r?.startTime == "07:00")
        #expect(r?.endTime == "09:00")
    }

    @Test("Overnight window keeps end < start for the client to handle")
    func overnightWindow() {
        let r = first("NO PARKING 9PM-6AM")
        #expect(r?.type == .no_parking)
        #expect(r?.startTime == "21:00")
        #expect(r?.endTime == "06:00")
    }

    @Test("Metered explicit window")
    func meteredWindow() {
        let r = first("METERED 8AM-6PM")
        #expect(r?.type == .metered)
        #expect(r?.startTime == "08:00")
        #expect(r?.endTime == "18:00")
    }

    @Test("Individual day mentions")
    func individualDays() {
        let r = first("9-11AM No Parking Mon Wed Fri")
        #expect(r?.type == .no_parking)
        #expect(r?.daysOfWeek == [1, 3, 5])
        #expect(r?.startTime == "09:00")
        #expect(r?.endTime == "11:00")
    }

    // MARK: - Meridiem inference

    @Test("Start meridiem inferred from end: 8-10PM → 20:00-22:00")
    func startMeridiemInferredPM() {
        let r = first("No Parking 8-10PM")
        #expect(r?.startTime == "20:00")
        #expect(r?.endTime == "22:00")
    }

    @Test("Meridiem inference does not over-apply: 11-2PM stays 11:00-14:00")
    func meridiemNotOverApplied() {
        let r = first("No Parking 11-2PM")
        #expect(r?.startTime == "11:00")
        #expect(r?.endTime == "14:00")
    }

    // MARK: - Duration limits

    @Test("Hour limit with a window is metered, window preferred")
    func hourLimitWithWindow() {
        let r = first("2 HR PARKING 9AM-6PM MON-FRI")
        #expect(r?.type == .metered)
        #expect(r?.daysOfWeek == [1, 2, 3, 4, 5])
        #expect(r?.startTime == "09:00")
        #expect(r?.endTime == "18:00")
        #expect(r?.durationMinutes == nil)
    }

    @Test("Hour-only limit is metered with durationMinutes")
    func hourOnlyLimit() {
        let r = first("2 HOUR PARKING")
        #expect(r?.type == .metered)
        #expect(r?.durationMinutes == 120)
    }

    @Test("Minute-only limit is metered with durationMinutes")
    func minuteOnlyLimit() {
        let r = first("90 MINUTE PARKING")
        #expect(r?.type == .metered)
        #expect(r?.durationMinutes == 90)
    }

    // MARK: - Type-only "anytime" signs

    @Test("Permit-only sign produces an all-day permit restriction")
    func permitOnly() {
        let r = first("PERMIT PARKING ONLY")
        #expect(r?.type == .permit)
        #expect(r?.daysOfWeek == [0, 1, 2, 3, 4, 5, 6])
    }

    @Test("No Parking Anytime produces an all-day no-parking restriction")
    func noParkingAnytime() {
        let r = first("NO PARKING ANYTIME")
        #expect(r?.type == .no_parking)
        #expect(r?.daysOfWeek == [0, 1, 2, 3, 4, 5, 6])
    }

    @Test("Tow Away zone maps to no parking")
    func towAway() {
        let r = first("TOW AWAY ZONE")
        #expect(r?.type == .no_parking)
    }

    // MARK: - Negative cases

    @Test("Junk text yields no restrictions")
    func junk() {
        #expect(parser.analyze(ocrText: "HELLO WORLD 123 xyz").restrictions.isEmpty)
    }

    @Test("Empty text yields no restrictions")
    func empty() {
        #expect(parser.analyze(ocrText: "").restrictions.isEmpty)
        #expect(parser.analyze(ocrText: "   \n  ").restrictions.isEmpty)
    }
}
#endif
