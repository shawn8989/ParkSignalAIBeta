import Foundation
import SwiftData

/// Deletes data and its owned rules in one save. Photo cleanup only considers the
/// explicitly deleted items, never a global sweep of partially imported iCloud data.
struct ParkingDataDeletion {
    let context: ModelContext
    func delete(spots: [ParkingSpot] = [], scans: [SignScan] = []) throws {
        var filenames = Set<String>()
        for spot in spots {
            filenames.formUnion(spot.streetPhotoFilenames)
            if let name = spot.lastScanPhotoFilename { filenames.insert(name) }
            for scan in spot.signScansList { filenames.formUnion(photoNames(scan)) }
        }
        let deletedIDs = Set(scans.map(\.id))
        for scan in scans {
            filenames.formUnion(photoNames(scan))
            for rule in scan.restrictionsList { context.delete(rule) }
            if let spot = scan.spot {
                if let next = spot.signScansList.filter({ !deletedIDs.contains($0.id) }).sorted(by: { $0.createdAt > $1.createdAt }).first {
                    spot.updateLastScan(from: next)
                } else { spot.lastScanText = nil; spot.lastScanPhotoFilename = nil; spot.lastScanAt = nil }
            }
            context.delete(scan)
        }
        for spot in spots { context.delete(spot) }
        do { try context.save() } catch { context.rollback(); throw error }
        let remainingSpots = try context.fetch(FetchDescriptor<ParkingSpot>())
        let remainingScans = try context.fetch(FetchDescriptor<SignScan>())
        let used = Set(remainingSpots.flatMap { $0.streetPhotoFilenames + [$0.lastScanPhotoFilename].compactMap { $0 } }
            + remainingScans.flatMap(photoNames))
        for filename in filenames.subtracting(used) { try ImageStore.deleteImage(named: filename, context: context) }
        Task { await ReminderCoordinator.shared.reconcile(context: context) }
    }
    private func photoNames(_ scan: SignScan) -> [String] {
        scan.photoFilenames + scan.additionalPhotoFilenames + [scan.photoFilename].compactMap { $0 }
    }
}
