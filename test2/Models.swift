import Foundation
import SwiftData
import CryptoKit

// MARK: - RestrictionType Enum

enum RestrictionType: String, Codable, Hashable, CaseIterable {
    case noParking = "No Parking"
    case streetCleaning = "Street Cleaning"
    case metered = "Metered"
    case permit = "Permit"
    case other = "Other"
    var displayName: String { rawValue }
}

// MARK: - User

@Model
final class User {
    @Attribute(.unique) var id: UUID
    var username: String
    var email: String
    var passwordHash: String
    var registeredAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Car.owner)
    var cars: [Car] = []

    init(id: UUID = UUID(), username: String, email: String, passwordHash: String, registeredAt: Date = .now) {
        self.id = id
        self.username = username
        self.email = email
        self.passwordHash = passwordHash
        self.registeredAt = registeredAt
    }
}

// MARK: - Car

@Model
final class Car {
    @Attribute(.unique) var id: UUID
    var nickname: String
    var licensePlate: String?
    var colorHex: String?
    var iconName: String

    @Relationship var owner: User?

    @Relationship(deleteRule: .cascade, inverse: \ParkSession.car)
    var sessions: [ParkSession] = []

    init(
        id: UUID = UUID(),
        nickname: String,
        licensePlate: String? = nil,
        colorHex: String? = nil,
        iconName: String = "car.fill",
        owner: User? = nil,
        sessions: [ParkSession] = []
    ) {
        self.id = id
        self.nickname = nickname
        self.licensePlate = licensePlate
        self.colorHex = colorHex
        self.iconName = iconName
        self.owner = owner
        self.sessions = sessions
    }
}

// MARK: - ParkingSpot

@Model
final class ParkingSpot {
    @Attribute(.unique) var id: UUID
    var location: String
    var latitude: Double
    var longitude: Double
    var streetSide: String // "left" or "right" or other
    @Relationship(deleteRule: .cascade, inverse: \Restriction.spot)
    var restrictions: [Restriction]

    @Relationship(deleteRule: .cascade, inverse: \SignScan.spot)
    var signScans: [SignScan] = []

    @Relationship(deleteRule: .cascade, inverse: \ParkSession.spot)
    var parkSessions: [ParkSession] = []

    var lastScanText: String?
    var lastScanPhotoFilename: String?
    var lastScanAt: Date?

    var streetPhotoFilenames: [String] = []
    var notes: String? = nil

    @Transient var alarmIDs: [UUID] = [UUID]()

    init(
        id: UUID = UUID(),
        location: String,
        latitude: Double,
        longitude: Double,
        streetSide: String,
        restrictions: [Restriction] = [],
        lastScanText: String? = nil,
        lastScanPhotoFilename: String? = nil,
        lastScanAt: Date? = nil,
        alarmIDs: [UUID] = []
    ) {
        self.id = id
        self.location = location
        self.latitude = latitude
        self.longitude = longitude
        self.streetSide = streetSide
        self.restrictions = restrictions
        self.lastScanText = lastScanText
        self.lastScanPhotoFilename = lastScanPhotoFilename
        self.lastScanAt = lastScanAt
        self.alarmIDs = alarmIDs
    }

    // Convenience helpers for managing scans and photos
    func attach(scan: SignScan) {
        if !self.signScans.contains(where: { $0.id == scan.id }) {
            scan.spot = self
            self.signScans.append(scan)
        } else {
            scan.spot = self
        }
        self.updateLastScan(from: scan)
    }

    func updateLastScan(from scan: SignScan) {
        self.lastScanText = scan.aiAnalysisText ?? scan.localAnalysisText ?? scan.ocrText
        self.lastScanPhotoFilename = scan.photoFilenames.first ?? scan.photoFilename ?? scan.additionalPhotoFilenames.first
        self.lastScanAt = scan.analyzedAt ?? scan.createdAt
    }

    func addStreetPhoto(filename: String) {
        if !self.streetPhotoFilenames.contains(filename) {
            self.streetPhotoFilenames.append(filename)
        }
    }
    
    var isCurrentlyParked: Bool { isCurrentlyParked(for: nil) }

    func isCurrentlyParked(for car: Car?) -> Bool {
        if let car {
            return parkSessions.contains { $0.car?.id == car.id && $0.endedAt == nil }
        } else {
            return parkSessions.contains { $0.endedAt == nil }
        }
    }

    @discardableResult
    func startParking(for car: Car? = nil, now: Date = .now) -> ParkSession {
        // End any existing active session for this car (or any if car is nil)
        if let car {
            if let idx = parkSessions.firstIndex(where: { $0.car?.id == car.id && $0.endedAt == nil }) {
                parkSessions[idx].endedAt = now
            }
        } else if let idx = parkSessions.firstIndex(where: { $0.endedAt == nil }) {
            parkSessions[idx].endedAt = now
        }
        let session = ParkSession(spot: self, startedAt: now, endedAt: nil, car: car)
        parkSessions.append(session)
        car?.sessions.append(session)
        return session
    }

    func endCurrentParking(for car: Car? = nil, at date: Date = .now) {
        if let car {
            if let idx = parkSessions.firstIndex(where: { $0.car?.id == car.id && $0.endedAt == nil }) {
                parkSessions[idx].endedAt = date
            }
        } else if let idx = parkSessions.firstIndex(where: { $0.endedAt == nil }) {
            parkSessions[idx].endedAt = date
        }
    }

    @discardableResult
    func toggleParking(for car: Car? = nil, now: Date = .now) -> ParkSession? {
        if isCurrentlyParked(for: car) {
            endCurrentParking(for: car, at: now)
            return nil
        } else {
            return startParking(for: car, now: now)
        }
    }
}

// MARK: - Restriction

@Model
final class Restriction {
    @Attribute(.unique) var id: UUID
    var type: RestrictionType
    var startTime: Date
    var endTime: Date
    var daysMask: Int = 0 // bitmask for days: Sunday bit0 ... Saturday bit6
    
    // Computed accessor for days of week as indices (0 = Sun ... 6 = Sat)
    var daysOfWeek: [Int] {
        get {
            (0...6).filter { (daysMask & (1 << $0)) != 0 }
        }
        set {
            let clamped = newValue.filter { (0...6).contains($0) }
            daysMask = clamped.reduce(0) { $0 | (1 << $1) }
        }
    }
    var sourceUser: UUID // the User.id that added this restriction
    var signPhotoFilename: String? // placeholder for image storage
    var ocrText: String? // AI-detected text from sign

    @Relationship var spot: ParkingSpot?
    @Relationship var scan: SignScan?

    init(
        id: UUID = UUID(),
        type: RestrictionType,
        startTime: Date,
        endTime: Date,
        daysOfWeek: [Int],
        sourceUser: UUID,
        signPhotoFilename: String? = nil,
        ocrText: String? = nil,
        spot: ParkingSpot? = nil,
        scan: SignScan? = nil
    ) {
        self.id = id
        self.type = type
        self.startTime = startTime
        self.endTime = endTime
        let clamped = daysOfWeek.filter { (0...6).contains($0) }
        self.daysMask = clamped.reduce(0) { $0 | (1 << $1) }
        self.sourceUser = sourceUser
        self.signPhotoFilename = signPhotoFilename
        self.ocrText = ocrText
        self.spot = spot
        self.scan = scan
    }
    
    var timeDescription: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let start = formatter.string(from: startTime)
        let end = formatter.string(from: endTime)
        return "\(start) - \(end)"
    }
    
    var daysDescription: String {
        // Sunday = 0 through Saturday = 6
        let daySymbols = Calendar.current.shortWeekdaySymbols
        let validIndices = daysOfWeek
            .filter { (0...6).contains($0) }
            .sorted()
        let days = validIndices.map { daySymbols[$0] }
        return days.isEmpty ? "None" : days.joined(separator: ", ")
    }
}

// MARK: - ParkSession (Parking History)
@Model
final class ParkSession {
    @Attribute(.unique) var id: UUID
    @Relationship var spot: ParkingSpot?
    @Relationship var car: Car?
    var startedAt: Date
    var endedAt: Date?
    
    var isActive: Bool { endedAt == nil }

    init(id: UUID = UUID(), spot: ParkingSpot? = nil, startedAt: Date = .now, endedAt: Date? = nil, car: Car? = nil) {
        self.id = id
        self.spot = spot
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.car = car
    }
}

// MARK: - SignScan (Street Sign pins captured from live scans)
@Model
final class SignScan {
    @Attribute(.unique) var id: UUID
    var latitude: Double
    var longitude: Double
    var ocrText: String
    var createdAt: Date
    var photoFilename: String?
    var additionalPhotoFilenames: [String] = []
    var photoFilenames: [String] = []

    // Detailed location metadata
    var horizontalAccuracy: Double?
    var altitude: Double?
    var heading: Double?
    var speed: Double?
    var mergedOCRText: String = ""

    var address: String?
    var status: String = "incomplete"
    var signalState: String? = nil

    // Segment metadata (curb segment assignment)
    var segmentCenterLat: Double?
    var segmentCenterLon: Double?
    var segmentRadius: Double?
    var segmentStreetSide: String?
    var segmentDirection: Double? // degrees 0...360

    @Relationship(deleteRule: .nullify, inverse: \Restriction.scan) var restrictions: [Restriction] = []

    // Analysis results
    var aiAnalysisText: String?
    var localAnalysisText: String?
    var analyzedAt: Date?

    // Who created the scan
    var sourceUser: UUID?

    // Optional attachment to a ParkingSpot
    @Relationship var spot: ParkingSpot?

    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        ocrText: String,
        createdAt: Date = .now,
        photoFilename: String? = nil,
        additionalPhotoFilenames: [String] = [],
        photoFilenames: [String] = [],
        mergedOCRText: String = "",
        horizontalAccuracy: Double? = nil,
        altitude: Double? = nil,
        heading: Double? = nil,
        speed: Double? = nil,
        address: String? = nil,
        status: String = "incomplete",
        signalState: String? = nil,
        aiAnalysisText: String? = nil,
        localAnalysisText: String? = nil,
        analyzedAt: Date? = nil,
        restrictions: [Restriction] = [],
        sourceUser: UUID? = nil,
        spot: ParkingSpot? = nil,
        segmentCenterLat: Double? = nil,
        segmentCenterLon: Double? = nil,
        segmentRadius: Double? = nil,
        segmentStreetSide: String? = nil,
        segmentDirection: Double? = nil
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.ocrText = ocrText
        self.createdAt = createdAt
        self.photoFilename = photoFilename
        self.additionalPhotoFilenames = additionalPhotoFilenames
        self.photoFilenames = photoFilenames
        self.horizontalAccuracy = horizontalAccuracy
        self.altitude = altitude
        self.heading = heading
        self.speed = speed
        self.mergedOCRText = mergedOCRText
        self.address = address
        self.status = status
        self.signalState = signalState
        self.segmentCenterLat = segmentCenterLat
        self.segmentCenterLon = segmentCenterLon
        self.segmentRadius = segmentRadius
        self.segmentStreetSide = segmentStreetSide
        self.segmentDirection = segmentDirection
        self.aiAnalysisText = aiAnalysisText
        self.localAnalysisText = localAnalysisText
        self.analyzedAt = analyzedAt
        self.restrictions = restrictions
        self.sourceUser = sourceUser
        self.spot = spot
    }

    // Update live location details for an existing scan
    func updateLocation(latitude: Double, longitude: Double, accuracy: Double? = nil, altitude: Double? = nil, heading: Double? = nil, speed: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = accuracy
        self.altitude = altitude
        self.heading = heading
        self.speed = speed
    }

    // Persist results from either AI or local analyzers
    func applyAnalysis(aiText: String? = nil, localText: String? = nil, at date: Date = .now) {
        if let aiText { self.aiAnalysisText = aiText }
        if let localText { self.localAnalysisText = localText }
        self.analyzedAt = date
    }

    // Add a photo used in analysis (keeps first as primary)
    func addPhoto(filename: String) {
        if self.photoFilename == nil {
            self.photoFilename = filename
        } else if !self.additionalPhotoFilenames.contains(filename) {
            self.additionalPhotoFilenames.append(filename)
        }
        if !self.photoFilenames.contains(filename) {
            self.photoFilenames.append(filename)
        }
    }

    var allPhotoFilenames: [String] {
        var arr: [String] = []
        if let primary = photoFilename { arr.append(primary) }
        arr.append(contentsOf: additionalPhotoFilenames)
        if !photoFilenames.isEmpty { // prefer new array ordering
            return photoFilenames
        }
        return arr
    }
}

// MARK: - Mock Data

struct MockData {
    static var users: [User] {
        [
            User(username: "alice", email: "alice@mail.com", passwordHash: "password".sha256),
            User(username: "bob", email: "bob@mail.com", passwordHash: "password123".sha256)
        ]
    }
    
    static var parkingSpots: [ParkingSpot] {
        let alice = users[0]
        let bob = users[1]
        let spot1 = ParkingSpot(
            location: "123 Main St",
            latitude: 37.7749, longitude: -122.4194,
            streetSide: "right"
        )
        let spot2 = ParkingSpot(
            location: "456 Oak Ave",
            latitude: 37.7751, longitude: -122.4183,
            streetSide: "left"
        )
        let restriction1 = Restriction(
            type: .streetCleaning,
            startTime: todayAt(hour: 8, minute: 0),
            endTime: todayAt(hour: 10, minute: 0),
            daysOfWeek: [2], // Tuesday (Sun=0)
            sourceUser: alice.id,
            ocrText: "No parking 8AM-10AM Tue",
            spot: spot1
        )
        let restriction2 = Restriction(
            type: .metered,
            startTime: todayAt(hour: 9, minute: 0),
            endTime: todayAt(hour: 18, minute: 0),
            daysOfWeek: [1, 2, 3, 4, 5], // Mon-Fri (Sun=0)
            sourceUser: bob.id,
            ocrText: "2 HR PARKING 9AM-6PM MON-FRI",
            spot: spot1
        )
        let restriction3 = Restriction(
            type: .noParking,
            startTime: todayAt(hour: 22, minute: 0),
            endTime: todayAt(hour: 6, minute: 0).addingTimeInterval(60*60*24),
            daysOfWeek: [0, 6], // Sun & Sat
            sourceUser: alice.id,
            ocrText: "No parking 10PM-6AM weekends",
            spot: spot2
        )
        spot1.restrictions = [restriction1, restriction2]
        spot2.restrictions = [restriction3]
        return [spot1, spot2]
    }
    
    static func todayAt(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? now
    }
}

// MARK: - Simple SHA256 Hash

extension String {
    var sha256: String {
        let digest = SHA256.hash(data: Data(self.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

