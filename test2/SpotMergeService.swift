import Foundation
import CoreLocation
import SwiftData

enum SpotMergeService {
    private static func normalized(_ s: String?) -> String {
        return (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Find an existing spot by normalized address or create a new one using the provided address/coordinate.
    /// If multiple spots share the same normalized address, merge them into a single primary spot.
    @MainActor
    static func findOrCreateSpot(address: String?, coordinate: CLLocationCoordinate2D, in context: ModelContext, preferredSide: String) -> ParkingSpot {
        let allSpots = (try? context.fetch(FetchDescriptor<ParkingSpot>())) ?? []
        let norm = normalized(address)
        let matches = allSpots.filter { normalized($0.location) == norm && !norm.isEmpty }

        let primary: ParkingSpot
        if let existing = matches.first {
            primary = existing
            // Refresh coordinates to latest
            primary.latitude = coordinate.latitude
            primary.longitude = coordinate.longitude
            if matches.count > 1 {
                deduplicate(spots: matches, keep: primary, in: context)
            }
        } else {
            let label: String
            if let addr = address, !addr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                label = addr
            } else {
                label = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
            }
            primary = ParkingSpot(
                location: label,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                streetSide: preferredSide,
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
