import Foundation
import CoreLocation

struct ParkingEligibility {
    let allowed: Bool
    let summary: String
    let warnings: [String]
    let nextRestriction: Date?
}

enum ParkingEligibilityEvaluator {
    static func evaluate(coordinate: CLLocationCoordinate2D, spotRestrictions: [Restriction], now: Date = Date()) async -> ParkingEligibility {
        let state = ParkingSignalEvaluator.status(for: spotRestrictions, now: now)
        switch state {
        case .gray:
            return ParkingEligibility(allowed: false, summary: "Check posted signs. Rules are missing or need review.", warnings: ["Parking eligibility is unknown."], nextRestriction: nil)
        case .red:
            return ParkingEligibility(allowed: false, summary: "A saved restriction is active. Check the posted signs.", warnings: [], nextRestriction: nil)
        case .blue, .purple:
            return ParkingEligibility(allowed: false, summary: state.label + ". Check the conditions on the sign.", warnings: ["A permit, payment or time limit may apply."], nextRestriction: nil)
        case .yellow, .green:
            return ParkingEligibility(allowed: true, summary: "No saved blocking rule is active. Always check all posted signs.", warnings: [], nextRestriction: spotRestrictions.first?.spot?.nextRestrictionDate(from: now))
        }
    }
}
