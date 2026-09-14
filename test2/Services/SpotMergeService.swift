import Foundation
import CoreLocation
import SwiftData

enum SpotMergeService {
    private static func normalized(_ s: String?) -> String {
        return (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// How close (meters) two scans must be to be considered the same physical spot.
    /// Wide enough to absorb GPS/geocoder jitter and different house numbers on one
    /// section of a block, narrow enough to keep distinct sections of a long block apart.
    static let proximityMeters: Double = 35

    /// Find an existing spot for this scan, or create one.
    ///
    /// Matching is by **street + proximity + curb side**, NOT by exact address string:
    /// - Side is inferred from the address's house-number parity (falls back to
    ///   `preferredSide` when there's no number), so opposite sides of the street are
    ///   never merged into one spot.
    /// - Same street + within `proximityMeters` + same side ⇒ same spot, so repeated
    ///   scans and different house numbers on one section stop spawning duplicates.
    /// The matched spot's coordinate is left as-is (a spot represents a block section,
    /// not wherever the latest sign happened to be scanned).
    @MainActor
    static func findOrCreateSpot(address: String?, coordinate: CLLocationCoordinate2D, in context: ModelContext, preferredSide: String) -> ParkingSpot {
        let allSpots = (try? context.fetch(FetchDescriptor<ParkingSpot>())) ?? []
        let side = DrivingSide.side(fromAddress: address) ?? preferredSide
        let street = DrivingSide.streetKey(from: address)
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        let matches = allSpots.filter { spot in
            let near = here.distance(from: CLLocation(latitude: spot.latitude, longitude: spot.longitude)) <= proximityMeters
            guard near else { return false }
            guard normalized(spot.streetSide) == normalized(side) else { return false }
            // If we know the street, require it to match so two nearby streets don't merge.
            if !street.isEmpty {
                return DrivingSide.streetKey(from: spot.location) == street
            }
            return true
        }

        let primary: ParkingSpot
        if let existing = matches.first {
            primary = existing
            if matches.count > 1 {
                deduplicate(spots: matches, keep: primary, in: context)
            }
        } else {
            let trimmed = address?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = (trimmed?.isEmpty == false) ? trimmed! : String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
            primary = ParkingSpot(
                location: label,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                streetSide: side,
                restrictions: []
            )
            context.insert(primary)
        }
        try? context.save()
        return primary
    }

    /// Merge duplicate spots into the primary spot by reassigning relationships and deleting duplicates.
    @MainActor
    static func deduplicate(spots: [ParkingSpot], keep primary: ParkingSpot, in context: ModelContext) {
        for s in spots {
            if s.id == primary.id { continue }
            // Move restrictions
            for r in s.restrictions {
                r.spot = primary
                if !primary.restrictions.contains(where: { $0.id == r.id }) {
                    primary.restrictions.append(r)
                }
            }
            // Move scans
            for sc in s.signScans {
                sc.spot = primary
                if !primary.signScans.contains(where: { $0.id == sc.id }) {
                    primary.signScans.append(sc)
                }
            }
            // Move sessions
            for sess in s.parkSessions {
                sess.spot = primary
            }
            // Delete duplicate spot
            context.delete(s)
        }
        try? context.save()
    }
}
