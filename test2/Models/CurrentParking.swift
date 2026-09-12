// CurrentParking.swift
import Foundation
import SwiftData

@Model
final class CurrentParking {
    var id: UUID = UUID()
    // Store the spot's id rather than a relationship: CurrentParking has no
    // reciprocal on ParkingSpot, and CloudKit requires every relationship to
    // have an inverse. This value is written when the user sets "current
    // parking"; storing the id keeps it CloudKit-safe.
    var spotID: UUID?
    var parkedAt: Date = Date.now

    init(id: UUID = UUID(), spotID: UUID? = nil, parkedAt: Date = Date.now) {
        self.id = id
        self.spotID = spotID
        self.parkedAt = parkedAt
    }
}
