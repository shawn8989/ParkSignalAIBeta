// ParkingHistory.swift
import Foundation
import SwiftData

@Model
final class ParkSession {
    @Attribute(.unique) var id: UUID
    @Relationship var spot: ParkingSpot?
    var startedAt: Date
    var endedAt: Date?

    init(id: UUID = UUID(), spot: ParkingSpot? = nil, startedAt: Date = .now, endedAt: Date? = nil) {
        self.id = id
        self.spot = spot
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

@Model
final class SignScan {
    @Attribute(.unique) var id: UUID
    var latitude: Double
    var longitude: Double
    var ocrText: String
    var createdAt: Date
    var photoFilename: String?

    init(id: UUID = UUID(), latitude: Double, longitude: Double, ocrText: String, createdAt: Date = .now, photoFilename: String? = nil) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.ocrText = ocrText
        self.createdAt = createdAt
        self.photoFilename = photoFilename
    }
}
