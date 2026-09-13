import Foundation

// Allowed types: street_cleaning, no_parking, metered, permit, other
// Pure Codable value types — opt out of the target's default main-actor isolation
// so their Codable conformance can be used off the main actor (e.g. background JSON decode).
nonisolated enum AIRestrictionType: String, Codable {
    case street_cleaning
    case no_parking
    case metered
    case permit
    case other
}

nonisolated struct AIRestriction: Codable {
    let type: AIRestrictionType
    let daysOfWeek: [Int]          // Sunday = 0 ... Saturday = 6
    let startTime: String          // "HH:mm" 24h local (use "00:00" if not applicable)
    let endTime: String            // "HH:mm" 24h local (use "00:00" if not applicable)
    let notes: String?
    let durationMinutes: Int?      // e.g., 180 for "3 HOUR PARKING"; nil if not a time limit
    // Optional, backward-compatible parse metadata (decode to nil when absent):
    var exceptHolidays: Bool? = nil   // sign said "holidays excepted" — restriction skips holidays
    var needsReview: Bool? = nil      // parse was low-confidence; prompt the user to confirm
}

nonisolated struct AIAnalysisResponse: Codable {
    let restrictions: [AIRestriction]
}
