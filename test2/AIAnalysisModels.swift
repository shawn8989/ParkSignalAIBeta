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
}

struct AIAnalysisResponse: Codable {
    let restrictions: [AIRestriction]
}
