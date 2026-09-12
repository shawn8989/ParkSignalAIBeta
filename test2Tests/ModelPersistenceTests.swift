#if canImport(Testing)
import Foundation
import SwiftData
import Testing
@testable import ParkSignal_AI

/// Persistence + relationship integrity for the SwiftData models.
///
/// These models are configured for CloudKit in the shipping app (no
/// `@Attribute(.unique)`, defaults on every stored property, inverse
/// relationships). CloudKit-rule enforcement happens at launch against the
/// real container; here we verify the schema builds, round-trips, and keeps
/// its relationships and default values in an in-memory store.
@Suite("Model persistence & relationships")
struct ModelPersistenceTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: User.self, Car.self, ParkingSpot.self, Restriction.self,
            ParkSession.self, SignScan.self, CurrentParking.self,
            configurations: config
        )
    }

    @MainActor
    @Test("Full graph inserts, saves, and round-trips with relationships intact")
    func fullGraphRoundTrip() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let user = User(username: "shawn", email: "s@example.com", passwordHash: "x".sha256)
        let car = Car(nickname: "Civic", owner: user)
        let spot = ParkingSpot(location: "1 Test St", latitude: 1.0, longitude: 2.0, streetSide: "right")
        let restriction = Restriction(type: .noParking, startTime: Date(), endTime: Date(),
                                      daysOfWeek: [1, 3, 5], sourceUser: user.id, spot: spot)
        let session = ParkSession(spot: spot, startedAt: Date(), endedAt: nil, car: car)
        let scan = SignScan(latitude: 1.0, longitude: 2.0, ocrText: "NO PARKING", spot: spot)
        let current = CurrentParking(spotID: spot.id)

        for m in [user, car, spot, restriction, session, scan, current] as [any PersistentModel] {
            ctx.insert(m)
        }
        try ctx.save()

        // Users & the User→cars inverse
        let users = try ctx.fetch(FetchDescriptor<User>())
        #expect(users.count == 1)
        #expect(users.first?.cars.count == 1)

        // Car→owner relationship + default value
        let cars = try ctx.fetch(FetchDescriptor<Car>())
        #expect(cars.first?.owner?.id == user.id)
        #expect(cars.first?.iconName == "car.fill")

        // ParkingSpot inverses
        let spots = try ctx.fetch(FetchDescriptor<ParkingSpot>())
        #expect(spots.first?.restrictions.count == 1)
        #expect(spots.first?.signScans.count == 1)
        #expect(spots.first?.parkSessions.count == 1)

        // Restriction→spot + bitmask-backed daysOfWeek survives a round-trip
        let restrictions = try ctx.fetch(FetchDescriptor<Restriction>())
        #expect(restrictions.first?.spot?.id == spot.id)
        #expect(restrictions.first?.daysOfWeek == [1, 3, 5])

        // CurrentParking stores the spot id (no relationship, CloudKit-safe)
        let currents = try ctx.fetch(FetchDescriptor<CurrentParking>())
        #expect(currents.first?.spotID == spot.id)
    }

    @MainActor
    @Test("status(for: ParkingSpot) reports an active no-parking window as red")
    func spotStatusRed() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 12; comps.minute = 0; comps.second = 0
        let now = Calendar.current.date(from: comps)!
        func at(_ hour: Int) -> Date {
            var c = comps; c.hour = hour
            return Calendar.current.date(from: c)!
        }

        let spot = ParkingSpot(location: "x", latitude: 0, longitude: 0, streetSide: "right")
        ctx.insert(spot)
        let r = Restriction(type: .noParking, startTime: at(8), endTime: at(18),
                            daysOfWeek: [], sourceUser: UUID(), spot: spot)
        ctx.insert(r)
        spot.restrictions.append(r)
        try ctx.save()

        #expect(ParkingSignalEvaluator.status(for: spot, now: now) == .red)
    }

    // MARK: - Restriction.daysOfWeek bitmask (pure)

    @Test("daysOfWeek round-trips through the daysMask bitmask")
    func daysMaskRoundTrip() {
        let r = Restriction(type: .metered, startTime: Date(), endTime: Date(),
                            daysOfWeek: [1, 3, 5], sourceUser: UUID())
        #expect(r.daysMask == (1 << 1 | 1 << 3 | 1 << 5))
        #expect(r.daysOfWeek == [1, 3, 5])
        r.daysOfWeek = [0, 6]
        #expect(r.daysMask == (1 << 0 | 1 << 6))
        #expect(r.daysOfWeek == [0, 6])
    }

    @Test("daysOfWeek clamps out-of-range indices")
    func daysClamp() {
        let r = Restriction(type: .other, startTime: Date(), endTime: Date(),
                            daysOfWeek: [7, -1, 3], sourceUser: UUID())
        #expect(r.daysOfWeek == [3])
        r.daysOfWeek = [2, 9, 4]
        #expect(r.daysOfWeek == [2, 4])
    }
}
#endif
