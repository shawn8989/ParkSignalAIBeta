import Foundation
import SwiftData

// MARK: - RestrictionType Enum

enum RestrictionType: String, Codable, Hashable, CaseIterable {
    case noParking = "No Parking"
    case streetCleaning = "Street Cleaning"
    case metered = "Metered"
    case other = "Other"
    
    var displayName: String {
        rawValue
    }
}

// MARK: - ParkingSpot Model

@Model
final class ParkingSpot {
    @Attribute(.unique) var id: UUID
    var location: String
    @Relationship(deleteRule: .cascade, inverse: \Restriction.spot)
    var restrictions: [Restriction]
    
    init(id: UUID = UUID(), location: String, restrictions: [Restriction] = []) {
        self.id = id
        self.location = location
        self.restrictions = restrictions
    }
}

// MARK: - Restriction Model

@Model
final class Restriction {
    @Attribute(.unique) var id: UUID
    var type: RestrictionType
    var startTime: Date
    var endTime: Date
    var daysOfWeek: [Int] // 0 = Sunday, 6 = Saturday
    
    @Relationship var spot: ParkingSpot?
    
    init(
        id: UUID = UUID(),
        type: RestrictionType,
        startTime: Date,
        endTime: Date,
        daysOfWeek: [Int],
        spot: ParkingSpot? = nil
    ) {
        self.id = id
        self.type = type
        self.startTime = startTime
        self.endTime = endTime
        self.daysOfWeek = daysOfWeek
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
        let calendar = Calendar.current
        let daySymbols = calendar.shortWeekdaySymbols // ["Sun", "Mon", ...]
        let validIndices = daysOfWeek.compactMap { $0 >= 0 && $0 < daySymbols.count ? $0 : nil }
        let days = validIndices.map { daySymbols[$0] }
        return days.joined(separator: ", ")
    }
}

// MARK: - Mock Data

struct MockData {
    static var parkingSpots: [ParkingSpot] {
        let now = Date()
        let spot1 = ParkingSpot(
            location: "123 Main St"
        )
        let spot2 = ParkingSpot(
            location: "456 Oak Ave"
        )
        
        let restriction1 = Restriction(
            type: .streetCleaning,
            startTime: todayAt(hour: 8, minute: 0),
            endTime: todayAt(hour: 10, minute: 0),
            daysOfWeek: [2], // Tuesday
            spot: spot1
        )
        let restriction2 = Restriction(
            type: .metered,
            startTime: todayAt(hour: 9, minute: 0),
            endTime: todayAt(hour: 18, minute: 0),
            daysOfWeek: [1, 2, 3, 4, 5], // Weekdays
            spot: spot1
        )
        let restriction3 = Restriction(
            type: .noParking,
            startTime: todayAt(hour: 22, minute: 0),
            endTime: todayAt(hour: 6, minute: 0).addingTimeInterval(60*60*24), // next day
            daysOfWeek: [0, 6], // Sunday, Saturday
            spot: spot2
        )
        spot1.restrictions = [restriction1, restriction2]
        spot2.restrictions = [restriction3]
        return [spot1, spot2]
    }
    
    // Helper for creating times today
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
