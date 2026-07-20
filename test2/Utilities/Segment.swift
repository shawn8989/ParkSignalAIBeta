import Foundation
import CoreLocation

// Street side relative to the curb. Currently supports left/right.
enum StreetSide: String, Codable, CaseIterable {
    case left
    case right
}

// Lightweight curb segment model used for grouping scans along a block side.
// This struct is intentionally not persisted; scans store their own segment metadata.
struct Segment: Hashable {
    var segmentCenter: CLLocationCoordinate2D
    var approximateRadius: Double = 15.0 // meters
    var streetSide: StreetSide
    var direction: Double? = nil // degrees 0...360 indicating street direction
    var scanIDs: [UUID] = []
}

extension Segment {
    static func == (lhs: Segment, rhs: Segment) -> Bool {
        let ld = lhs.direction.map { round($0 * 10) / 10 }
        let rd = rhs.direction.map { round($0 * 10) / 10 }
        return lhs.segmentCenter.latitude == rhs.segmentCenter.latitude &&
        lhs.segmentCenter.longitude == rhs.segmentCenter.longitude &&
        lhs.approximateRadius == rhs.approximateRadius &&
        lhs.streetSide == rhs.streetSide &&
        ld == rd
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(segmentCenter.latitude.bitPattern)
        hasher.combine(segmentCenter.longitude.bitPattern)
        hasher.combine(approximateRadius.bitPattern)
        hasher.combine(streetSide)
        if let d = direction { hasher.combine(Int(round(d * 10))) }
    }
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

    /// Smallest signed angle difference in degrees between a and b.
    static func angleDiff(_ a: Double, _ b: Double) -> Double {
        var d = fmod((a - b + 540), 360) - 180
        if d < -180 { d += 360 }
        return abs(d)
    }

    /// Circular mean of two angles in degrees.
    static func averageAngles(_ a: Double, _ b: Double) -> Double {
        let ar = a * .pi / 180
        let br = b * .pi / 180
        let x = cos(ar) + cos(br)
        let y = sin(ar) + sin(br)
        let mean = atan2(y, x) * 180 / .pi
        return (mean < 0) ? mean + 360 : mean
    }
    
    /// Initial bearing in degrees from coordinate a to b (0=N, 90=E)
    static func bearingDegrees(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lon1 = a.longitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let lon2 = b.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        var brng = atan2(y, x) * 180 / .pi
        if brng < 0 { brng += 360 }
        return brng
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
    static func nearestSegmentIndex(to location: CLLocationCoordinate2D, in segments: [Segment], side: StreetSide, direction: Double?, within radius: Double) -> Int? {
        var bestIndex: Int? = nil
        var bestDistance = Double.greatestFiniteMagnitude
        for (idx, seg) in segments.enumerated() where seg.streetSide == side {
            if let d1 = direction, let d2 = seg.direction {
                // Require roughly aligned directions (<= 35 degrees apart)
                if SegmentUtils.angleDiff(d1, d2) > 35 { continue }
            }
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
            let dir = s.segmentDirection
            // Round to ~1e-5 degrees (~1m) to stabilize keys
            let key = String(format: "%0.5f,%0.5f,%@", center.latitude, center.longitude, side.rawValue)
            if var seg = dict[key] {
                seg.scanIDs.append(s.id)
                if let dir, let existing = seg.direction {
                    seg.direction = SegmentUtils.averageAngles(existing, dir)
                } else if let dir {
                    seg.direction = dir
                }
                dict[key] = seg
            } else {
                dict[key] = Segment(segmentCenter: center, approximateRadius: radius, streetSide: side, direction: dir, scanIDs: [s.id])
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
        
        // Infer a direction if none provided, to enable curb-aligned rendering
        var inferredDirection = heading
        if inferredDirection == nil {
            // 1) Reuse any existing direction from scans on the same side
            if let s = existingScans.first(where: { (($0.segmentStreetSide ?? $0.spot?.streetSide)?.lowercased() ?? "") == side.rawValue && ($0.segmentDirection != nil || $0.heading != nil) }) {
                inferredDirection = s.segmentDirection ?? s.heading
            }
        }
        if inferredDirection == nil {
            // 2) Infer from nearest prior scan raw coordinates on the same side
            let candidates = existingScans.filter { (($0.segmentStreetSide ?? $0.spot?.streetSide)?.lowercased() ?? "") == side.rawValue }
            if let nearest = candidates.min(by: {
                let a = CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                let b = CLLocationCoordinate2D(latitude: $1.latitude, longitude: $1.longitude)
                return SegmentUtils.distanceMeters(a, currentLocation) < SegmentUtils.distanceMeters(b, currentLocation)
            }) {
                let a = CLLocationCoordinate2D(latitude: nearest.latitude, longitude: nearest.longitude)
                inferredDirection = SegmentUtils.bearingDegrees(from: a, to: currentLocation)
            }
        }

        // Attempt to find nearest segment on same side within radius
        let idx = nearestSegmentIndex(to: currentLocation, in: segs, side: side, direction: inferredDirection, within: defaultRadius)
        if let idx {
            var seg = segs[idx]
            seg.scanIDs.append(scan.id)
            // Update scan metadata to match this segment
            scan.segmentCenterLat = seg.segmentCenter.latitude
            scan.segmentCenterLon = seg.segmentCenter.longitude
            scan.segmentRadius = seg.approximateRadius
            scan.segmentStreetSide = seg.streetSide.rawValue
            // Also carry forward direction if available
            if let segDir = seg.direction { scan.segmentDirection = segDir }
            else if let d = inferredDirection { scan.segmentDirection = d }
            return seg
        } else {
            // Create a new segment centered at current location
            let seg = Segment(segmentCenter: currentLocation, approximateRadius: defaultRadius, streetSide: side, direction: inferredDirection, scanIDs: [scan.id])
            scan.segmentCenterLat = currentLocation.latitude
            scan.segmentCenterLon = currentLocation.longitude
            scan.segmentRadius = defaultRadius
            scan.segmentStreetSide = side.rawValue
            scan.segmentDirection = inferredDirection
            return seg
        }
    }
}

