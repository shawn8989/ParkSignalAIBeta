#if canImport(Testing)
import Foundation
import Testing
@testable import ParkSignal_AI

/// Deterministic tests for the curb-signal engine. Every case pins `now` to a
/// fixed same-day reference and builds restriction windows in `Calendar.current`,
/// so results are independent of the machine's timezone.
@Suite("ParkingSignalEvaluator")
struct ParkingSignalEvaluatorTests {

    /// Today at the given hour/minute in the current calendar.
    private func at(_ hour: Int, _ minute: Int = 0, ref: Date) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: ref)
        c.hour = hour; c.minute = minute; c.second = 0
        return Calendar.current.date(from: c)!
    }

    private func todayWeekday0_6(_ ref: Date) -> Int {
        (Calendar.current.component(.weekday, from: ref) + 6) % 7
    }

    private func restriction(_ type: RestrictionType, _ startHour: Int, _ endHour: Int,
                             days: [Int], ref: Date) -> Restriction {
        Restriction(type: type,
                    startTime: at(startHour, 0, ref: ref),
                    endTime: at(endHour, 0, ref: ref),
                    daysOfWeek: days,
                    sourceUser: UUID())
    }

    // MARK: - [Restriction] overload

    @Test("Empty restrictions → gray")
    func emptyGray() {
        let now = at(12, 0, ref: Date())
        #expect(ParkingSignalEvaluator.status(for: [Restriction](), now: now) == .gray)
    }

    @Test("Active no-parking window → red")
    func noParkingActiveRed() {
        let now = at(12, 0, ref: Date())
        let r = restriction(.noParking, 8, 18, days: [], ref: now)
        #expect(ParkingSignalEvaluator.status(for: [r], now: now) == .red)
    }

    @Test("Active street-cleaning window → red")
    func streetCleaningActiveRed() {
        let now = at(12, 0, ref: Date())
        let r = restriction(.streetCleaning, 8, 18, days: [], ref: now)
        #expect(ParkingSignalEvaluator.status(for: [r], now: now) == .red)
    }

    @Test("Active permit window → blue")
    func permitActiveBlue() {
        let now = at(12, 0, ref: Date())
        let r = restriction(.permit, 8, 18, days: [], ref: now)
        #expect(ParkingSignalEvaluator.status(for: [r], now: now) == .blue)
    }

    @Test("Active metered window → purple")
    func meteredActivePurple() {
        let now = at(12, 0, ref: Date())
        let r = restriction(.metered, 8, 18, days: [], ref: now)
        #expect(ParkingSignalEvaluator.status(for: [r], now: now) == .purple)
    }

    @Test("Red wins over a simultaneously-active permit")
    func redBeatsBlue() {
        let now = at(12, 0, ref: Date())
        let noPark = restriction(.noParking, 8, 18, days: [], ref: now)
        let permit = restriction(.permit, 8, 18, days: [], ref: now)
        #expect(ParkingSignalEvaluator.status(for: [permit, noPark], now: now) == .red)
    }

    @Test("Illegal restriction starting within leadMinutes → yellow")
    func illegalSoonYellow() {
        let now = at(12, 0, ref: Date())
        let today = todayWeekday0_6(now)
        let r = Restriction(type: .noParking,
                            startTime: at(12, 10, ref: now),
                            endTime: at(14, 0, ref: now),
                            daysOfWeek: [today],
                            sourceUser: UUID())
        #expect(ParkingSignalEvaluator.status(for: [r], now: now, leadMinutes: 15) == .yellow)
    }

    @Test("Illegal restriction starting beyond leadMinutes → green")
    func illegalLaterGreen() {
        let now = at(12, 0, ref: Date())
        let today = todayWeekday0_6(now)
        let r = Restriction(type: .noParking,
                            startTime: at(12, 30, ref: now),
                            endTime: at(14, 0, ref: now),
                            daysOfWeek: [today],
                            sourceUser: UUID())
        #expect(ParkingSignalEvaluator.status(for: [r], now: now, leadMinutes: 15) == .green)
    }

    @Test("Non-active, non-illegal metered later today → green")
    func inactiveMeteredGreen() {
        let now = at(12, 0, ref: Date())
        let r = restriction(.metered, 20, 22, days: [], ref: now)
        #expect(ParkingSignalEvaluator.status(for: [r], now: now) == .green)
    }

    @Test("No-parking scheduled only for a different weekday → green today")
    func differentDayGreen() {
        let now = at(12, 0, ref: Date())
        let tomorrow = (todayWeekday0_6(now) + 1) % 7
        let r = restriction(.noParking, 8, 18, days: [tomorrow], ref: now)
        #expect(ParkingSignalEvaluator.status(for: [r], now: now) == .green)
    }

    // MARK: - AIAnalysisResponse overload

    @Test("Duration-only metered analysis is treated active → purple")
    func aiDurationOnlyPurple() {
        let now = at(12, 0, ref: Date())
        let a = AIAnalysisResponse(restrictions: [
            AIRestriction(type: .metered, daysOfWeek: [], startTime: "00:00",
                          endTime: "00:00", notes: nil, durationMinutes: 120)
        ])
        #expect(ParkingSignalEvaluator.status(for: a, now: now) == .purple)
    }

    @Test("AI no-parking window active → red")
    func aiNoParkingRed() {
        let now = at(12, 0, ref: Date())
        let a = AIAnalysisResponse(restrictions: [
            AIRestriction(type: .no_parking, daysOfWeek: [], startTime: "08:00",
                          endTime: "18:00", notes: nil, durationMinutes: nil)
        ])
        #expect(ParkingSignalEvaluator.status(for: a, now: now) == .red)
    }

    @Test("Empty AI analysis → gray")
    func aiEmptyGray() {
        let now = at(12, 0, ref: Date())
        let a = AIAnalysisResponse(restrictions: [])
        #expect(ParkingSignalEvaluator.status(for: a, now: now) == .gray)
    }

    // MARK: - Overnight windows

    @Test("Overnight restriction from yesterday is still red in the early morning")
    func overnightYesterdayRed() {
        let now = at(2, 0, ref: Date())               // today 02:00
        let yesterday = (todayWeekday0_6(now) + 6) % 7 // yesterday's weekday
        let r = Restriction(type: .noParking,
                            startTime: at(22, 0, ref: now),
                            endTime: at(6, 0, ref: now),
                            daysOfWeek: [yesterday],
                            sourceUser: UUID())
        #expect(ParkingSignalEvaluator.status(for: [r], now: now) == .red)
    }

    @Test("Overnight restriction is green after its window ends")
    func overnightAfterEndGreen() {
        let now = at(7, 0, ref: Date())                // today 07:00 (after 06:00 end)
        let yesterday = (todayWeekday0_6(now) + 6) % 7
        let r = Restriction(type: .noParking,
                            startTime: at(22, 0, ref: now),
                            endTime: at(6, 0, ref: now),
                            daysOfWeek: [yesterday],
                            sourceUser: UUID())
        #expect(ParkingSignalEvaluator.status(for: [r], now: now) == .green)
    }
}
#endif
