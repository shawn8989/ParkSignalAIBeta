#if canImport(Testing)
import Foundation
import SwiftData
import UIKit
import Testing
@testable import ParkSignal_AI

@Suite("Photo sync via PhotoBlob")
@MainActor
struct PhotoStoreTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: PhotoBlob.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    private func sampleImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    @Test("Saving with a context creates a synced blob; loading rehydrates it")
    func rehydratesFromBlob() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let name = try ImageStore.saveJPEG(sampleImage(), context: ctx)

        // The local file exists AND a blob was stored.
        #expect(ImageStore.loadImage(named: name) != nil)
        #expect(try ctx.fetch(FetchDescriptor<PhotoBlob>()).count == 1)

        // Simulate another device: the model (blob) synced, but the local file isn't there.
        try FileManager.default.removeItem(at: ImageStore.url(for: name))
        #expect(ImageStore.loadImage(named: name) == nil)              // no file, no context
        #expect(ImageStore.loadImage(named: name, context: ctx) != nil) // rehydrated from blob
    }

    @Test("Old referenced files get blobs; deleting their scan removes owned rules and photos")
    func backfillAndDeleteScan() throws {
        let schema = Schema([ParkingSpot.self, SignScan.self, Restriction.self, PhotoBlob.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let ctx = container.mainContext
        let name = try ImageStore.saveJPEG(sampleImage())
        defer { try? ImageStore.deleteImage(named: name) }
        let spot = ParkingSpot(location: "Sample", latitude: 1, longitude: 2, streetSide: "right")
        let scan = SignScan(latitude: 1, longitude: 2, ocrText: "NO PARKING", photoFilename: name, spot: spot)
        ctx.insert(spot); ctx.insert(scan)
        ctx.insert(Restriction(type: .noParking, startTime: Date(), endTime: Date(), daysOfWeek: [1], sourceUser: UUID(), spot: spot, scan: scan))
        spot.updateLastScan(from: scan)
        try ctx.save()
        try ImageStore.backfillReferencedPhotos(in: ctx)
        try ImageStore.backfillReferencedPhotos(in: ctx)
        #expect(try ctx.fetch(FetchDescriptor<PhotoBlob>()).count == 1)
        try ParkingDataDeletion(context: ctx).delete(scans: [scan])
        #expect(try ctx.fetch(FetchDescriptor<Restriction>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<PhotoBlob>()).isEmpty)
        #expect(spot.lastScanPhotoFilename == nil)
        #expect(try ctx.fetch(FetchDescriptor<ParkingSpot>()).count == 1)
    }

    @Test("Deleting a photo removes its blob")
    func deleteRemovesBlob() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let name = try ImageStore.saveJPEG(sampleImage(), context: ctx)
        #expect(try ctx.fetch(FetchDescriptor<PhotoBlob>()).count == 1)
        try ImageStore.deleteImage(named: name, context: ctx)
        #expect(try ctx.fetch(FetchDescriptor<PhotoBlob>()).isEmpty)
    }
}
#endif
