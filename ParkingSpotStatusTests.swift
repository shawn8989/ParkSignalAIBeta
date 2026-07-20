#if canImport(Testing)
import Foundation
import SwiftData
import Testing

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

        let cal = Calendar(identifier: .gregorian)
        let ref = ISO8601DateFormatter().date(from: "2024-01-01T08:30:00Z")! // Tue in UTC
        var comps = DateComponents(); comps.hour = 8; comps.minute = 0
        let start = cal.date(from: comps) ?? ref
        let end = cal.date(byAdding: .hour, value: 2, to: start) ?? ref
        let r = Restriction(type: .noParking, startTime: start, endTime: end, daysOfWeek: [2], sourceUser: UUID(), spot: spot)
        context.insert(r)
        spot.restrictions.append(r)
        try context.save()

        let active = spot.isRestrictedNow(at: ref)
        #expect(active == true)
    }
}
#endif
