import CoreData
import SwiftData
import Testing
@testable import ParkSignal_AI

@MainActor
@Suite("CloudKit schema preparation")
struct CloudSchemaPreparationTests {
    @Test func fullModelIncludesUnpopulatedOptionalAttributes() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: ParkSignalModelSchema.types))
        let current = try #require(model.entitiesByName["CurrentParking"])
        #expect(current.attributesByName["spotID"] != nil)
        let restriction = try #require(model.entitiesByName["Restriction"])
        for name in ["durationMinutes", "reviewReasons", "needsReview", "signPhotoFilename", "ocrText"] {
            #expect(restriction.attributesByName[name] != nil, "Missing schema attribute: \(name)")
        }
        #expect(model.entities.count == 8)
    }
}
