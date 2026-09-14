#if canImport(Testing)
import Foundation
import SwiftData
import CoreLocation
import Testing
@testable import ParkSignal_AI

@Suite("Address parity → side")
struct DrivingSideParityTests {
    @Test("House number is read from the address")
    func houseNumber() {
        #expect(DrivingSide.houseNumber(from: "120 Main St, SF, CA") == 120)
        #expect(DrivingSide.houseNumber(from: "121A Main St") == 121)
        #expect(DrivingSide.houseNumber(from: "Main St") == nil)
        #expect(DrivingSide.houseNumber(from: "") == nil)
        #expect(DrivingSide.houseNumber(from: nil) == nil)
    }

    @Test("Even → right, odd → left, none → nil")
    func sideFromParity() {
        #expect(DrivingSide.side(fromAddress: "120 Main St, SF") == "right")
        #expect(DrivingSide.side(fromAddress: "121 Main St, SF") == "left")
        #expect(DrivingSide.side(fromAddress: "Main St") == nil)
    }

    @Test("Street key drops the house number, city and state")
    func streetKey() {
        #expect(DrivingSide.streetKey(from: "120 Main St, San Francisco, CA") == "main st")
        #expect(DrivingSide.streetKey(from: "148 Main St, SF, CA") == "main st")
        #expect(DrivingSide.streetKey(from: "Oak Ave") == "oak ave")
        #expect(DrivingSide.streetKey(from: "") == "")
    }
}

@Suite("SpotMergeService dedup by street + proximity + side")
@MainActor
struct SpotMergeServiceTests {
    // The container must outlive the context, so each test holds it.
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: User.self, Car.self, ParkingSpot.self, Restriction.self,
            ParkSession.self, SignScan.self, CurrentParking.self,
            configurations: config
        )
    }

    private let sf = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

    @Test("Repeated scan at the same address reuses one spot")
    func sameAddressReuses() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let a = SpotMergeService.findOrCreateSpot(address: "120 Main St, SF, CA", coordinate: sf, in: ctx, preferredSide: "right")
        let b = SpotMergeService.findOrCreateSpot(address: "120 Main St, SF, CA", coordinate: sf, in: ctx, preferredSide: "right")
        #expect(a.id == b.id)
        #expect(try ctx.fetch(FetchDescriptor<ParkingSpot>()).count == 1)
    }

    @Test("Opposite parity = opposite side = two spots")
    func oppositeSidesSplit() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let even = SpotMergeService.findOrCreateSpot(address: "120 Main St, SF, CA", coordinate: sf, in: ctx, preferredSide: "right")
        let odd = SpotMergeService.findOrCreateSpot(address: "121 Main St, SF, CA", coordinate: sf, in: ctx, preferredSide: "right")
        #expect(even.id != odd.id)
        #expect(even.streetSide == "right")
        #expect(odd.streetSide == "left")
        #expect(try ctx.fetch(FetchDescriptor<ParkingSpot>()).count == 2)
    }

    @Test("Different house numbers on the same side + section merge")
    func sameSideDifferentNumberMerges() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let a = SpotMergeService.findOrCreateSpot(address: "120 Main St, SF, CA", coordinate: sf, in: ctx, preferredSide: "right")
        let b = SpotMergeService.findOrCreateSpot(address: "124 Main St, SF, CA", coordinate: sf, in: ctx, preferredSide: "right")
        #expect(a.id == b.id)
        #expect(try ctx.fetch(FetchDescriptor<ParkingSpot>()).count == 1)
    }

    @Test("Far apart on the same street stays as distinct sections")
    func farApartSplits() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let far = CLLocationCoordinate2D(latitude: 37.7767, longitude: -122.4194) // ~200 m north
        let a = SpotMergeService.findOrCreateSpot(address: "120 Main St, SF, CA", coordinate: sf, in: ctx, preferredSide: "right")
        let b = SpotMergeService.findOrCreateSpot(address: "120 Main St, SF, CA", coordinate: far, in: ctx, preferredSide: "right")
        #expect(a.id != b.id)
    }

    @Test("Matching a spot does not overwrite its coordinate")
    func doesNotOverwriteCoordinate() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let a = SpotMergeService.findOrCreateSpot(address: "120 Main St, SF, CA", coordinate: sf, in: ctx, preferredSide: "right")
        let originalLat = a.latitude
        let jitter = CLLocationCoordinate2D(latitude: 37.77499, longitude: -122.4194) // ~10 m away
        let b = SpotMergeService.findOrCreateSpot(address: "120 Main St, SF, CA", coordinate: jitter, in: ctx, preferredSide: "right")
        #expect(a.id == b.id)
        #expect(b.latitude == originalLat)
    }
}
#endif
