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
    let startTime: String          // "HH:mm" 24h local (use "00:00" if not applicable)
    let endTime: String            // "HH:mm" 24h local (use "00:00" if not applicable)
    let notes: String?
    let durationMinutes: Int?      // e.g., 180 for "3 HOUR PARKING"; nil if not a time limit
}

struct AIAnalysisResponse: Codable {
    let restrictions: [AIRestriction]
}
