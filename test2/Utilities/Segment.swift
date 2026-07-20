import Foundation
import CoreLocation

// Street side relative to the curb. Currently supports left/right.
enum StreetSide: String, Codable, CaseIterable {
    case left
    case right
}

// Lightweight curb segment model used for grouping scans along a block side.
// This struct is intentionally not persisted; scans store their own segment metadata.
struct Segment {
    var segmentCenter: CLLocationCoordinate2D
    var approximateRadius: Double = 15.0 // meters
    var streetSide: StreetSide
    var scanIDs: [UUID] = []
}

// MARK: - Segment Utilities

enum SegmentUtils {
    /// Haversine distance between two coordinates in meters.
    static func distanceMeters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let R = 6_371_000.0 // Earth radius in meters
        let lat1 = a.latitude * .pi / 180
        let lon1 = a.longitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let lon2 = b.longitude * .pi / 180
        let dlat = lat2 - lat1
        let dlon = lon2 - lon1
        let aa = sin(dlat/2) * sin(dlat/2) + cos(lat1) * cos(lat2) * sin(dlon/2) * sin(dlon/2)
        let c = 2 * atan2(sqrt(aa), sqrt(1-aa))
        return R * c
    }
}

// MARK: - Segment Manager

/// Minimal manager for assigning scans to curb segments based on proximity and side of street.
/// This avoids app-wide rewrites by attaching segment metadata directly on SignScan instances.
struct SegmentManager {
    /// Determine the preferred street side for a scan.
    /// - Parameters:
    ///   - preferred: Explicit preferred side (e.g., from the ParkingSpot.streetSide) if available.
    ///   - scanSpotSide: The associated spot's side as a raw string ("left"/"right").
    /// - Returns: StreetSide value; defaults to `.right` when unknown.
    static func resolveSide(preferred: StreetSide?, scanSpotSide: String?) -> StreetSide {
        if let preferred { return preferred }
        if let s = scanSpotSide?.lowercased(), let side = StreetSide(rawValue: s) { return side }
        // Default to right-hand traffic as a fallback
        return .right
    }

    /// Find the nearest existing segment on the same side within the given radius.
    static func nearestSegmentIndex(to location: CLLocationCoordinate2D, in segments: [Segment], side: StreetSide, within radius: Double) -> Int? {
        var bestIndex: Int? = nil
        var bestDistance = Double.greatestFiniteMagnitude
        for (idx, seg) in segments.enumerated() where seg.streetSide == side {
            let d = SegmentUtils.distanceMeters(seg.segmentCenter, location)
            if d <= max(radius, seg.approximateRadius), d < bestDistance {
                bestDistance = d
                bestIndex = idx
            }
        }
        return bestIndex
    }

    /// Build segments from existing scans by using each scan's stored segment metadata.
    static func segments(from scans: [SignScan]) -> [Segment] {
        var dict: [String: Segment] = [:] // key by center+side rounded
        for s in scans {
            let radius = s.segmentRadius ?? 15.0
            let side = StreetSide(rawValue: (s.segmentStreetSide ?? "").lowercased()) ?? .right
            let center = CLLocationCoordinate2D(latitude: s.segmentCenterLat ?? s.latitude, longitude: s.segmentCenterLon ?? s.longitude)
            // Round to ~1e-5 degrees (~1m) to stabilize keys
            let key = String(format: "%0.5f,%0.5f,%@", center.latitude, center.longitude, side.rawValue)
            if var seg = dict[key] {
                seg.scanIDs.append(s.id)
                dict[key] = seg
            } else {
                dict[key] = Segment(segmentCenter: center, approximateRadius: radius, streetSide: side, scanIDs: [s.id])
            }
        }
        return Array(dict.values)
    }

    /// Assign the given scan to an appropriate segment, creating a new one if needed. The scan will be updated in-place with segment metadata.
    @discardableResult
    static func assign(scan: SignScan, existingScans: [SignScan], currentLocation: CLLocationCoordinate2D, heading: Double?, preferredSide: StreetSide?, defaultRadius: Double = 15.0) -> Segment {
        // Determine side preference
        let side = resolveSide(preferred: preferredSide, scanSpotSide: scan.spot?.streetSide)
        // Build segments from existing scans
        var segs = segments(from: existingScans)
        // Attempt to find nearest segment on same side within radius
        let idx = nearestSegmentIndex(to: currentLocation, in: segs, side: side, within: defaultRadius)
        if let idx {
            var seg = segs[idx]
            seg.scanIDs.append(scan.id)
            // Update scan metadata to match this segment
            scan.segmentCenterLat = seg.segmentCenter.latitude
            scan.segmentCenterLon = seg.segmentCenter.longitude
            scan.segmentRadius = seg.approximateRadius
            scan.segmentStreetSide = seg.streetSide.rawValue
            return seg
        } else {
            // Create a new segment centered at current location
            let seg = Segment(segmentCenter: currentLocation, approximateRadius: defaultRadius, streetSide: side, scanIDs: [scan.id])
            scan.segmentCenterLat = currentLocation.latitude
            scan.segmentCenterLon = currentLocation.longitude
            scan.segmentRadius = defaultRadius
            scan.segmentStreetSide = side.rawValue
            return seg
        }
    }
}
