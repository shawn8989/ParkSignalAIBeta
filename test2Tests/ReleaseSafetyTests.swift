import Foundation
import SwiftData
import Testing
@testable import ParkSignal_AI

@MainActor
@Suite("Free v1 release safety")
struct ReleaseSafetyTests {
    @Test func exceptionsDoNotInvertWeekdays() {
        let result = ParkingTextParser().analyze(ocrText: "NO PARKING MON-FRI 8AM-6PM HOLIDAYS EXCEPTED")
        #expect(result.restrictions.first?.daysOfWeek == [1,2,3,4,5])
        #expect(result.restrictions.first?.requiresReview == true)
        #expect(ParkingSignalEvaluator.status(for: result) == .gray)
    }
    @Test(arguments: ["EXCEPT SAT SUN", "EXCEPT SAT-SUN", "EXCEPT SAT & SUN", "SAT-SUN EXCEPTED"])
    func adjacentAndRangeExceptions(_ exception: String) {
        let result = ParkingTextParser().analyze(ocrText: "NO PARKING 8AM-10AM " + exception)
        #expect(result.restrictions.first?.daysOfWeek == [1,2,3,4,5])
        #expect(result.restrictions.first?.requiresReview == false)
    }
    @Test func preserveHoursAndMaximumStay() {
        let result = ParkingTextParser().analyze(ocrText: "2 HOUR PARKING MON-FRI 9AM-6PM")
        #expect(result.restrictions.first?.type == .time_limited)
        #expect(result.restrictions.first?.durationMinutes == 120)
        #expect(result.restrictions.first?.startTime == "09:00")
        #expect(result.restrictions.first?.endTime == "18:00")
        #expect(result.restrictions.first?.requiresReview == false)
    }
    @Test(arguments: ["NO PARKING 1ST & 3RD TUE 8AM-10AM", "NO PARKING DEC 1-APR 1 3AM-7AM", "NO PARKING SCHOOL DAYS 8AM-3PM", "2 HOUR PARKING 9AM-6PM PERMIT HOLDERS EXEMPT", "NO STANDING EXCEPT TRUCKS LOADING 7AM-7PM MON-FRI"])
    func unsupportedNeverGreen(_ sign: String) {
        let result = ParkingTextParser().analyze(ocrText: sign)
        #expect(!result.restrictions.isEmpty)
        #expect(result.restrictions.allSatisfy { $0.requiresReview })
        #expect(ParkingSignalEvaluator.status(for: result) == .gray)
    }
    @Test func allRelationshipsAreOptional() {
        let schema = Schema([User.self,Car.self,ParkingSpot.self,Restriction.self,ParkSession.self,SignScan.self,CurrentParking.self,PhotoBlob.self])
        for entity in schema.entities {
            for property in entity.properties {
                if let relationship = property as? Schema.Relationship {
                    #expect(relationship.isOptional, "\(entity.name).\(relationship.name) must be CloudKit-compatible")
                }
            }
        }
    }
    @Test func legacyStoreMigratesWithoutLosingGraph() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("migration.store")
        let spotID = UUID()
        do {
            let schema = Schema([LegacyStoreSchema.User.self,LegacyStoreSchema.Car.self,LegacyStoreSchema.ParkingSpot.self,LegacyStoreSchema.Restriction.self,LegacyStoreSchema.ParkSession.self,LegacyStoreSchema.SignScan.self,LegacyStoreSchema.CurrentParking.self,LegacyStoreSchema.PhotoBlob.self])
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let context = container.mainContext
            let spot = LegacyStoreSchema.ParkingSpot(id: spotID, location: "Migration spot", latitude: 1, longitude: 2, streetSide: "right")
            let car = LegacyStoreSchema.Car(nickname: "Saved car")
            let scan = LegacyStoreSchema.SignScan(latitude: 1, longitude: 2, ocrText: "NO PARKING", spot: spot)
            let rule = LegacyStoreSchema.Restriction(type: .noParking, startTime: Date(), endTime: Date(), daysOfWeek: [1,3], sourceUser: UUID(), spot: spot, scan: scan)
            context.insert(spot); context.insert(car); context.insert(scan); context.insert(rule)
            context.insert(LegacyStoreSchema.ParkSession(spot: spot, car: car))
            context.insert(LegacyStoreSchema.PhotoBlob(filename: "existing.jpg", data: Data([1,2,3])))
            try context.save()
        }
        let schema = Schema([User.self,Car.self,ParkingSpot.self,Restriction.self,ParkSession.self,SignScan.self,CurrentParking.self,PhotoBlob.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let context = container.mainContext
        let spot = try #require(context.fetch(FetchDescriptor<ParkingSpot>()).first)
        #expect(spot.id == spotID)
        #expect(spot.restrictionsList.count == 1)
        #expect(spot.signScansList.count == 1)
        #expect(spot.parkSessionsList.first?.car?.nickname == "Saved car")
        #expect(spot.restrictionsList.first?.needsReview == true)
        #expect(spot.signScansList.first?.needsReview == true)
        #expect(try context.fetch(FetchDescriptor<PhotoBlob>()).first?.data == Data([1,2,3]))
        #expect(ParkingSignalEvaluator.status(for: spot) == .gray)
    }
    @Test func reanalysisReplacesOnlyReviewedScan() throws {
        let schema = Schema([ParkingSpot.self,SignScan.self,Restriction.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        let spot = ParkingSpot(location: "Test", latitude: 1, longitude: 2, streetSide: "right")
        let scan = SignScan(latitude: 1, longitude: 2, ocrText: "2 HR", spot: spot)
        context.insert(spot); context.insert(scan)
        let other = Restriction(type: .permit, startTime: Date(), endTime: Date(), daysOfWeek: [0], sourceUser: UUID(), spot: spot)
        context.insert(other)
        let draft = ReviewedRestriction(type: .timeLimited, days: [1,2,3,4,5], start: Date(), end: Date(), durationMinutes: 120, needsReview: false, reviewReasons: [])
        let service = ScanReviewService(context: context)
        _ = try service.save([draft], for: spot, scan: scan, text: "2 HR", photoFilename: nil, sourceUser: UUID())
        _ = try service.save([draft], for: spot, scan: scan, text: "2 HR", photoFilename: nil, sourceUser: UUID())
        #expect(try context.fetch(FetchDescriptor<Restriction>()).count == 2)
        #expect(scan.restrictionsList.count == 1)
        #expect(scan.restrictionsList.first?.durationMinutes == 120)
        #expect(spot.restrictionsList.contains { $0.id == other.id })
        // Excluding one proposal cannot silently discard an unsupported condition
        // present in the original sign text.
        _ = try service.save([draft], for: spot, scan: scan, text: "2 HR EXCEPT HOLIDAYS", photoFilename: nil, sourceUser: UUID(), sourceRequiresReview: true)
        #expect(scan.needsReview)
        #expect(scan.restrictionsList.allSatisfy { $0.needsReview })
        #expect(ParkingSignalEvaluator.status(for: spot) == .gray)
    }
}
