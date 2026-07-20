#if canImport(Testing)
import Foundation
import SwiftData
import Testing
@testable import ParkSignal_AI

@Suite("ParkingSpot status helpers")
struct ParkingSpotStatusTests {
    @MainActor
    @Test("nextRestrictionDate finds the next future start")
    func nextRestrictionDateFuture() async throws {
        let container = try ModelContainer(for: ParkingSpot.self, Restriction.self)
        let context = container.mainContext
        let spot = ParkingSpot(location: "Test", latitude: 0, longitude: 0, streetSide: "right", restrictions: [])
        context.insert(spot)

        let cal = Calendar(identifier: .gregorian)
        let now = ISO8601DateFormatter().date(from: "2024-01-01T12:00:00Z")!
        // Add a restriction on Tuesday 09:00
        var comps = DateComponents(); comps.hour = 9; comps.minute = 0
        let start = cal.date(from: comps) ?? now
        let end = cal.date(byAdding: .hour, value: 2, to: start) ?? now
        let r = Restriction(type: .streetCleaning, startTime: start, endTime: end, daysOfWeek: [2], sourceUser: UUID(), spot: spot)
        context.insert(r)
        spot.restrictions.append(r)
        try context.save()

        let next = spot.nextRestrictionDate(from: now)
        #expect(next != nil)
    }

    @MainActor
    @Test("isRestrictedNow detects active window")
    func isRestrictedNowActive() async throws {
        let container = try ModelContainer(for: ParkingSpot.self, Restriction.self)
        let context = container.mainContext
        let spot = ParkingSpot(location: "Test", latitude: 0, longitude: 0, streetSide: "right", restrictions: [])
        context.insert(spot)

        // Build "today at 08:30" in the current calendar/timezone, with a
        // restriction window 08:00–10:00 on today's weekday, so the test is
        // deterministic regardless of the machine's timezone.
        let cal = Calendar.current
        var refComps = cal.dateComponents([.year, .month, .day], from: Date())
        refComps.hour = 8; refComps.minute = 30
        let ref = cal.date(from: refComps)!
        let weekday0_6 = (cal.component(.weekday, from: ref) + 6) % 7
        var startComps = refComps; startComps.minute = 0
        let start = cal.date(from: startComps)!
        let end = cal.date(byAdding: .hour, value: 2, to: start)!
        let r = Restriction(type: .noParking, startTime: start, endTime: end, daysOfWeek: [weekday0_6], sourceUser: UUID(), spot: spot)
        context.insert(r)
        spot.restrictions.append(r)
        try context.save()

        let active = spot.isRestrictedNow(at: ref)
        #expect(active == true)
    }
}
#endif
