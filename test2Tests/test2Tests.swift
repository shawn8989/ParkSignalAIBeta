#if canImport(Testing)
//
//  test2Tests.swift
//  test2Tests
//
//  Created by shunathon Owens on 11/18/25.
//

import Foundation
import Testing
@testable import ParkSignal_AI

@Suite("Formatting tests for Restriction and utilities")
struct RestrictionFormattingTests {

    @Test("daysDescription for weekdays")
    func daysDescriptionWeekdays() async throws {
        let r = Restriction(
            type: .metered,
            startTime: Date(),
            endTime: Date(),
            daysOfWeek: [1, 2, 3, 4, 5], // Mon-Fri (Sun=0)
            sourceUser: UUID()
        )
        let expected = [1, 2, 3, 4, 5]
            .map { Calendar.current.shortWeekdaySymbols[$0] }
            .joined(separator: ", ")
        #expect(r.daysDescription == expected)
    }

    @Test("daysDescription for empty selection shows 'None'")
    func daysDescriptionEmpty() async throws {
        let r = Restriction(
            type: .other,
            startTime: Date(),
            endTime: Date(),
            daysOfWeek: [],
            sourceUser: UUID()
        )
        #expect(r.daysDescription == "None")
    }

    @Test("timeDescription matches DateFormatter(.short)")
    func timeDescriptionMatchesFormatter() async throws {
        var comps = DateComponents()
        comps.year = 2024
        comps.month = 1
        comps.day = 1
        comps.hour = 9
        comps.minute = 0
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(from: comps)!
        comps.hour = 17
        comps.minute = 30
        let end = cal.date(from: comps)!

        let r = Restriction(
            type: .permit,
            startTime: start,
            endTime: end,
            daysOfWeek: [2],
            sourceUser: UUID()
        )

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let expected = "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        #expect(r.timeDescription == expected)
    }

    @Test("SHA256 hashing returns 64 hex chars")
    func sha256HashLength() async throws {
        let hash = "password".sha256
        #expect(hash.count == 64)
    }
}
#endif
