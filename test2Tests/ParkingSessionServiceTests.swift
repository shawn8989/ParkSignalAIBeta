#if canImport(Testing)
import Foundation
import SwiftData
import Testing
@testable import ParkSignal_AI

/// Records which alert side effects the service triggered.
@MainActor
final class SpyParkingAlerts: ParkingAlerts {
    var scheduledSpotReminders: [UUID] = []
    var cancelledSpotReminders: [UUID] = []
    var scheduledMoveAlerts: [(car: UUID, spot: UUID)] = []
    var cancelledMoveAlerts: [UUID] = []

    func scheduleSpotReminders(for spot: ParkingSpot) async { scheduledSpotReminders.append(spot.id) }
    func cancelSpotReminders(for spot: ParkingSpot) async { cancelledSpotReminders.append(spot.id) }
    func scheduleMoveAlert(for car: Car, at spot: ParkingSpot) async { scheduledMoveAlerts.append((car.id, spot.id)) }
    func cancelMoveAlerts(forCarID carID: UUID) async { cancelledMoveAlerts.append(carID) }
}

@MainActor
@Suite("ParkingSessionService")
struct ParkingSessionServiceTests {

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let spy: SpyParkingAlerts
        let service: ParkingSessionService

        func openSessions() throws -> [ParkSession] {
            try context.fetch(FetchDescriptor<ParkSession>()).filter { $0.endedAt == nil }
        }

        func makeSpot(_ name: String) -> ParkingSpot {
            let spot = ParkingSpot(location: name, latitude: 0, longitude: 0, streetSide: "right")
            context.insert(spot)
            return spot
        }

        func makeCar(_ name: String) -> Car {
            let car = Car(nickname: name)
            context.insert(car)
            return car
        }
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainer(
            for: User.self, Car.self, ParkingSpot.self, Restriction.self,
            ParkSession.self, SignScan.self, CurrentParking.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let spy = SpyParkingAlerts()
        let service = ParkingSessionService(context: container.mainContext, alerts: spy)
        return Fixture(container: container, context: container.mainContext, spy: spy, service: service)
    }

    @Test("Parking car B leaves car A parked")
    func parkingOneCarLeavesOthersAlone() async throws {
        let f = try makeFixture()
        let a = f.makeCar("A"), b = f.makeCar("B")
        let spot1 = f.makeSpot("1 Main"), spot2 = f.makeSpot("2 Main")

        await f.service.park(a, at: spot1, scheduleMoveAlert: false)
        await f.service.park(b, at: spot2, scheduleMoveAlert: false)

        let open = try f.openSessions()
        #expect(open.count == 2)
        #expect(open.contains { $0.car?.id == a.id && $0.spot?.id == spot1.id })
        #expect(open.contains { $0.car?.id == b.id && $0.spot?.id == spot2.id })
        #expect(!f.spy.cancelledMoveAlerts.contains(a.id))
    }

    @Test("Re-parking a car ends its old session and cancels the old spot's reminders")
    func reparkMovesCar() async throws {
        let f = try makeFixture()
        let car = f.makeCar("A")
        let old = f.makeSpot("Old"), new = f.makeSpot("New")

        await f.service.park(car, at: old, scheduleMoveAlert: false)
        await f.service.park(car, at: new, scheduleMoveAlert: false)

        let open = try f.openSessions()
        #expect(open.count == 1)
        #expect(open.first?.spot?.id == new.id)
        #expect(f.spy.cancelledSpotReminders == [old.id])
        #expect(f.spy.cancelledMoveAlerts == [car.id])
        #expect(f.spy.scheduledSpotReminders == [old.id, new.id])
    }

    @Test("Weekly reminders are cancelled only when the last session at a spot ends")
    func remindersSurviveWhileSpotOccupied() async throws {
        let f = try makeFixture()
        let a = f.makeCar("A"), b = f.makeCar("B")
        let spot = f.makeSpot("Shared")

        await f.service.park(a, at: spot, scheduleMoveAlert: false)
        await f.service.park(b, at: spot, scheduleMoveAlert: false)

        await f.service.end(a)
        #expect(f.spy.cancelledSpotReminders.isEmpty)

        await f.service.end(b)
        #expect(f.spy.cancelledSpotReminders == [spot.id])
    }

    @Test("Ending a car's session cancels that car's move alert")
    func endCancelsMoveAlert() async throws {
        let f = try makeFixture()
        let car = f.makeCar("A")
        let spot = f.makeSpot("Here")

        await f.service.park(car, at: spot, scheduleMoveAlert: true)
        #expect(f.spy.scheduledMoveAlerts.count == 1)

        await f.service.end(car)
        #expect(try f.openSessions().isEmpty)
        #expect(f.spy.cancelledMoveAlerts == [car.id])
    }

    @Test("Car-less parking never touches car sessions")
    func carlessIsolated() async throws {
        let f = try makeFixture()
        let car = f.makeCar("A")
        let spot1 = f.makeSpot("1"), spot2 = f.makeSpot("2")

        await f.service.park(car, at: spot1, scheduleMoveAlert: false)
        await f.service.park(nil, at: spot2)
        await f.service.park(nil, at: spot1)

        let open = try f.openSessions()
        #expect(open.count == 2)
        #expect(open.contains { $0.car?.id == car.id && $0.spot?.id == spot1.id })
        #expect(open.contains { $0.car == nil && $0.spot?.id == spot1.id })
    }

    @Test("End All at a spot ends every session there, including cars")
    func endAllEndsCarSessions() async throws {
        let f = try makeFixture()
        let car = f.makeCar("A")
        let spot = f.makeSpot("Here"), elsewhere = f.makeSpot("Elsewhere")
        let other = f.makeCar("B")

        await f.service.park(car, at: spot, scheduleMoveAlert: false)
        await f.service.park(nil, at: spot)
        await f.service.park(other, at: elsewhere, scheduleMoveAlert: false)

        await f.service.endAll(at: spot)

        let open = try f.openSessions()
        #expect(open.count == 1)
        #expect(open.first?.car?.id == other.id)
        #expect(f.spy.cancelledSpotReminders == [spot.id])
        #expect(f.spy.cancelledMoveAlerts == [car.id])
    }
}
#endif
