import CoreData
import CloudKit
import Foundation
import SwiftData

enum ParkSignalModelSchema {
    static let types: [any PersistentModel.Type] = [
        User.self, Car.self, ParkingSpot.self, Restriction.self,
        CurrentParking.self, ParkSession.self, SignScan.self, PhotoBlob.self
    ]
}

#if DEBUG
/// Explicit developer action only. Never opens the user's persisted store.
@MainActor
enum CloudSchemaPreparation {
    enum PreparationError: LocalizedError {
        case cloudKitUnavailable
        var errorDescription: String? {
            "Schema preparation requires a signed, iCloud-enabled device or simulator."
        }
    }

    static func initializeDevelopmentSchema(cloudKitEnabled: Bool) throws {
        guard cloudKitEnabled else { throw PreparationError.cloudKitUnavailable }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParkSignal-schema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try autoreleasepool {
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: ParkSignalModelSchema.types) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let description = NSPersistentStoreDescription(url: directory.appendingPathComponent("schema.sqlite"))
            description.shouldAddStoreAsynchronously = false
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.SOTech.ParkSignalAI")
            options.databaseScope = .private
            description.cloudKitContainerOptions = options
            let container = NSPersistentCloudKitContainer(name: "ParkSignalSchemaPreparation", managedObjectModel: model)
            container.persistentStoreDescriptions = [description]
            var loadError: Error?
            container.loadPersistentStores { _, error in loadError = error }
            if let loadError { throw loadError }
            defer {
                for store in container.persistentStoreCoordinator.persistentStores {
                    try? container.persistentStoreCoordinator.remove(store)
                }
            }
            try container.initializeCloudKitSchema()
        }
    }
}
#endif
