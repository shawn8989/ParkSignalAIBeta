import Foundation
import CoreLocation

enum CurbGeometry {
    /// Convert meters to angular distance in radians given Earth radius.
    private static let earthRadiusMeters: Double = 6_371_000.0

    /// Returns a destination coordinate given a start coordinate, a bearing in degrees (0=N), and a distance in meters.
    static func coordinate(from start: CLLocationCoordinate2D, bearingDegrees: Double, distanceMeters: Double) -> CLLocationCoordinate2D {
        let brng = bearingDegrees * .pi / 180
        let dist = distanceMeters / earthRadiusMeters
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180

        let sinLat1 = sin(lat1)
        let cosLat1 = cos(lat1)
        let sinDist = sin(dist)
        let cosDist = cos(dist)

        let lat2 = asin(sinLat1 * cosDist + cosLat1 * sinDist * cos(brng))
        let lon2 = lon1 + atan2(sin(brng) * sinDist * cosLat1, cosDist - sinLat1 * sin(lat2))

        let latDeg = lat2 * 180 / .pi
        var lonDeg = lon2 * 180 / .pi
        // Normalize lon to [-180, 180]
        lonDeg = fmod((lonDeg + 540), 360) - 180
        return CLLocationCoordinate2D(latitude: latDeg, longitude: lonDeg)
    }

    /// Normalize a heading to [0, 360).
    static func normalizedHeading(_ h: Double) -> Double {
        var x = fmod(h, 360)
        if x < 0 { x += 360 }
        return x
    }

    /// Compute a curb-aligned polyline centered at `center`, aligned with `directionDegrees` (street direction),
    /// shifted to the left/right side by `offsetMeters`, and extending `lengthMeters` total.
    /// Returns two points (start, end) suitable for a MapPolyline.
    static func curbAlignedPolyline(center: CLLocationCoordinate2D, directionDegrees: Double, sideRaw: String?, lengthMeters: Double = 20.0, offsetMeters: Double = 4.5) -> [CLLocationCoordinate2D] {
        let dir = normalizedHeading(directionDegrees)
        let half = lengthMeters / 2.0
        // Street direction endpoints (before curb offset)
        let a = coordinate(from: center, bearingDegrees: dir + 180, distanceMeters: half)
        let b = coordinate(from: center, bearingDegrees: dir, distanceMeters: half)
        // Perpendicular bearing for curb offset
        let side = (sideRaw ?? "").lowercased()
        let perp = side == "left" ? dir - 90 : dir + 90
        let offA = coordinate(from: a, bearingDegrees: perp, distanceMeters: offsetMeters)
        let offB = coordinate(from: b, bearingDegrees: perp, distanceMeters: offsetMeters)
        return [offA, offB]
    }
}
