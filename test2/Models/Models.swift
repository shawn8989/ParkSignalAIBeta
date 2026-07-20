import Foundation
import SwiftData

// MARK: - RestrictionType

enum RestrictionType: String, Codable, Hashable, CaseIterable {
    case noParking = "No Parking"
    case streetCleaning = "Street Cleaning"
    case metered = "Metered"
    case permit = "Permit"
    case other = "Other"

    var displayName: String {
        rawValue
    }
}

// MARK: - ParkingSpot

@Model
final class ParkingSpot {
    @Attribute(.unique) var id: UUID
    /// Human-readable address or label, e.g. "123 Main St, San Francisco".
    var location: String
    var latitude: Double
    var longitude: Double
    /// Curb side relative to travel direction: "left", "right", or "unknown".
    var streetSide: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Restriction.spot)
    var restrictions: [Restriction]

    @Relationship(deleteRule: .cascade, inverse: \SignScan.spot)
    var scans: [SignScan]

    @Relationship(deleteRule: .cascade, inverse: \ParkSession.spot)
    var parkSessions: [ParkSession]

    init(
        id: UUID = UUID(),
        location: String,
        latitude: Double = 0,
        longitude: Double = 0,
        streetSide: String = "unknown",
        createdAt: Date = .now,
        restrictions: [Restriction] = [],
        scans: [SignScan] = [],
        parkSessions: [ParkSession] = []
    ) {
        self.id = id
        self.location = location
        self.latitude = latitude
        self.longitude = longitude
        self.streetSide = streetSide
        self.createdAt = createdAt
        self.restrictions = restrictions
        self.scans = scans
        self.parkSessions = parkSessions
    }

    var activeSession: ParkSession? {
        parkSessions.first { $0.endedAt == nil }
    }

    /// Filenames of every sign photo attached to this spot (via scans and restrictions), deduplicated.
    var photoFilenames: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in scans.sorted(by: { $0.createdAt < $1.createdAt }).compactMap(\.photoFilename)
            + restrictions.compactMap(\.signPhotoFilename) {
            if seen.insert(name).inserted { result.append(name) }
        }
        return result
    }
}

// MARK: - Restriction

@Model
final class Restriction {
    @Attribute(.unique) var id: UUID
    var type: RestrictionType
    var startTime: Date
    var endTime: Date
    var daysOfWeek: [Int] // 0 = Sunday ... 6 = Saturday
    var notes: String?
    /// Raw OCR text this restriction was parsed from, if any.
    var ocrText: String?
    /// Filename (in ImageStore) of the sign photo this restriction came from, if any.
    var signPhotoFilename: String?

    var spot: ParkingSpot?

    init(
        id: UUID = UUID(),
        type: RestrictionType,
        startTime: Date,
        endTime: Date,
        daysOfWeek: [Int],
        notes: String? = nil,
        ocrText: String? = nil,
        signPhotoFilename: String? = nil,
        spot: ParkingSpot? = nil
    ) {
        self.id = id
        self.type = type
        self.startTime = startTime
        self.endTime = endTime
        self.daysOfWeek = daysOfWeek
        self.notes = notes
        self.ocrText = ocrText
        self.signPhotoFilename = signPhotoFilename
        self.spot = spot
    }

    var timeDescription: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let start = formatter.string(from: startTime)
        let end = formatter.string(from: endTime)
        return "\(start) - \(end)"
    }

    var daysDescription: String {
        let daySymbols = Calendar.current.shortWeekdaySymbols // ["Sun", "Mon", ...]
        let days = daysOfWeek.compactMap { $0 >= 0 && $0 < daySymbols.count ? daySymbols[$0] : nil }
        return days.isEmpty ? "Every day" : days.joined(separator: ", ")
    }
}

// MARK: - SignScan

@Model
final class SignScan {
    @Attribute(.unique) var id: UUID
    var latitude: Double
    var longitude: Double
    var ocrText: String
    var createdAt: Date
    var photoFilename: String?
    var address: String?
    /// "complete" once analyzed and saved; "pending" otherwise.
    var status: String

    // Curb-segment metadata (see SegmentManager).
    var segmentCenterLat: Double?
    var segmentCenterLon: Double?
    var segmentRadius: Double?
    var segmentStreetSide: String?

    var spot: ParkingSpot?

    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        ocrText: String,
        createdAt: Date = .now,
        photoFilename: String? = nil,
        address: String? = nil,
        status: String = "complete",
        spot: ParkingSpot? = nil
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.ocrText = ocrText
        self.createdAt = createdAt
        self.photoFilename = photoFilename
        self.address = address
        self.status = status
        self.spot = spot
    }
}

// MARK: - ParkSession

@Model
final class ParkSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?

    var spot: ParkingSpot?

    init(id: UUID = UUID(), startedAt: Date = .now, endedAt: Date? = nil, spot: ParkingSpot? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.spot = spot
    }

    var isActive: Bool { endedAt == nil }

    var duration: TimeInterval {
        (endedAt ?? .now).timeIntervalSince(startedAt)
    }
}
