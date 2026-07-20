// CurrentParking.swift
import Foundation
import SwiftData

@Model
final class CurrentParking {
    @Attribute(.unique) var id: UUID
    @Relationship var spot: ParkingSpot?
    var parkedAt: Date

    init(id: UUID = UUID(), spot: ParkingSpot? = nil, parkedAt: Date = .now) {
        self.id = id
        self.spot = spot
        self.parkedAt = parkedAt
    }
}
