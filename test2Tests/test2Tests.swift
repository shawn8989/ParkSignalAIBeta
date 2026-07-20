//
//  test2Tests.swift
//  test2Tests
//

import Foundation
import Testing
@testable import test2

@MainActor
struct ParkingTextParserTests {

    private let parser = ParkingTextParser()

    @Test func parsesStreetCleaningSign() throws {
        let result = parser.analyze(ocrText: "NO PARKING 8AM-10AM TUESDAY STREET CLEANING")
        #expect(result.restrictions.count == 1)
        let r = try #require(result.restrictions.first)
        #expect(r.type == .street_cleaning)
        #expect(r.startTime == "08:00")
        #expect(r.endTime == "10:00")
        #expect(r.daysOfWeek == [2]) // Tuesday
    }

    @Test func parsesWeekdayRange() throws {
        let result = parser.analyze(ocrText: "NO PARKING 7AM TO 9AM MON-FRI")
        let r = try #require(result.restrictions.first)
        #expect(r.type == .no_parking)
        #expect(r.daysOfWeek == [1, 2, 3, 4, 5])
        #expect(r.startTime == "07:00")
        #expect(r.endTime == "09:00")
    }

    @Test func keepsOvernightWindowEndBeforeStart() throws {
        let result = parser.analyze(ocrText: "NO PARKING 10PM TO 6AM DAILY")
        let r = try #require(result.restrictions.first)
        #expect(r.startTime == "22:00")
        #expect(r.endTime == "06:00") // end < start signals an overnight window
        #expect(r.daysOfWeek == [0, 1, 2, 3, 4, 5, 6])
    }

    @Test func detectsMeteredSign() throws {
        let result = parser.analyze(ocrText: "METERED PARKING 9AM-6PM")
        let r = try #require(result.restrictions.first)
        #expect(r.type == .metered)
        #expect(r.startTime == "09:00")
        #expect(r.endTime == "18:00")
    }

    @Test func emptyTextYieldsNoRestrictions() {
        let result = parser.analyze(ocrText: "")
        #expect(result.restrictions.isEmpty)
    }
}

@MainActor
struct ParkingSignalEvaluatorTests {

    /// Noon today — safely inside same-day windows regardless of timezone.
    private var noon: Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 12
        comps.minute = 0
        return Calendar.current.date(from: comps)!
    }

    private var todayWeekday0_6: Int {
        (Calendar.current.component(.weekday, from: noon) + 6) % 7
    }

    @Test func activeNoParkingIsRed() {
        let analysis = AIAnalysisResponse(restrictions: [
            AIRestriction(type: .no_parking, daysOfWeek: [todayWeekday0_6], startTime: "11:00", endTime: "13:00")
        ])
        #expect(ParkingSignalEvaluator.status(for: analysis, now: noon) == .red)
    }

    @Test func activeMeterIsPurple() {
        let analysis = AIAnalysisResponse(restrictions: [
            AIRestriction(type: .metered, daysOfWeek: [todayWeekday0_6], startTime: "09:00", endTime: "18:00")
        ])
        #expect(ParkingSignalEvaluator.status(for: analysis, now: noon) == .purple)
    }

    @Test func inactiveRestrictionIsGreen() {
        let analysis = AIAnalysisResponse(restrictions: [
            AIRestriction(type: .no_parking, daysOfWeek: [todayWeekday0_6], startTime: "02:00", endTime: "03:00")
        ])
        #expect(ParkingSignalEvaluator.status(for: analysis, now: noon) == .green)
    }

    @Test func restrictionStartingSoonIsYellow() {
        let analysis = AIAnalysisResponse(restrictions: [
            AIRestriction(type: .street_cleaning, daysOfWeek: [todayWeekday0_6], startTime: "12:10", endTime: "14:00")
        ])
        #expect(ParkingSignalEvaluator.status(for: analysis, now: noon, leadMinutes: 15) == .yellow)
    }

    @Test func noRestrictionsIsGray() {
        let analysis = AIAnalysisResponse(restrictions: [])
        #expect(ParkingSignalEvaluator.status(for: analysis, now: noon) == .gray)
    }
}
