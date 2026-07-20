import Foundation

// Allowed types: street_cleaning, no_parking, metered, permit, other
enum AIRestrictionType: String, Codable {
    case street_cleaning
    case no_parking
    case metered
    case permit
    case other
}

struct AIRestriction: Codable {
    let type: AIRestrictionType
    let daysOfWeek: [Int]          // Sunday = 0 ... Saturday = 6
    let startTime: String          // "HH:mm" 24h local
    let endTime: String            // "HH:mm" 24h local
    let notes: String?
    /// For time-limited parking ("2 Hour Parking") where the limit is a duration, not a window.
    let durationMinutes: Int?

    init(
        type: AIRestrictionType,
        daysOfWeek: [Int],
        startTime: String,
        endTime: String,
        notes: String? = nil,
        durationMinutes: Int? = nil
    ) {
        self.type = type
        self.daysOfWeek = daysOfWeek
        self.startTime = startTime
        self.endTime = endTime
        self.notes = notes
        self.durationMinutes = durationMinutes
    }
}

struct AIAnalysisResponse: Codable {
    let restrictions: [AIRestriction]
}
