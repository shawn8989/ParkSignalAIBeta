import Foundation
import CoreLocation
import Combine

// MARK: - City Models
struct CityInfo: Equatable {
    let cityName: String
}

struct CityRestriction: Equatable {
    let type: RestrictionType
    let daysOfWeek: [Int] // 0=Sun..6=Sat
    let startTime: String // HH:mm
    let endTime: String   // HH:mm
    let notes: String?
}

// Internal zone representation for quick proximity checks
private struct CityZone {
    let name: String
    let center: CLLocationCoordinate2D
    let radiusMeters: Double
    let restrictions: [CityRestriction]
}

struct ZoneOverlay: Equatable, Hashable {
    let name: String
    let center: CLLocationCoordinate2D
    let radiusMeters: Double

    static func == (lhs: ZoneOverlay, rhs: ZoneOverlay) -> Bool {
        return lhs.name == rhs.name &&
        lhs.radiusMeters == rhs.radiusMeters &&
        lhs.center.latitude == rhs.center.latitude &&
        lhs.center.longitude == rhs.center.longitude
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(radiusMeters)
        hasher.combine(center.latitude)
        hasher.combine(center.longitude)
    }
}

@MainActor
final class ParkingDataProvider: ObservableObject {
    static let shared = ParkingDataProvider()

    @Published var matchedCity: CityInfo? = nil

    // Cache of currently loaded zones for the matched city
    private var zones: [CityZone] = []
    private var loadedCityKey: String? = nil // e.g. "sf", "nyc"

    private init() {}

    // MARK: - Public API

    /// Detects the city for the provided location and loads a realistic sample dataset once.
    func bootstrapIfNeeded(currentLocation: CLLocationCoordinate2D) async {
        // Determine which city this coordinate belongs to (simple bounding boxes for demo)
        let key: String?
        if Self.isInSanFrancisco(currentLocation) { key = "sf" }
        else if Self.isInNewYorkCity(currentLocation) { key = "nyc" }
        else if Self.isInLosAngelesArea(currentLocation) { key = "la" }
        else { key = nil }

        // If nothing changed, do nothing
        guard key != loadedCityKey else { return }

        loadedCityKey = key
        switch key {
        case "sf":
            matchedCity = CityInfo(cityName: "San Francisco")
            zones = Self.sampleZones_SF()
        case "nyc":
            matchedCity = CityInfo(cityName: "New York City")
            zones = Self.sampleZones_NYC()
        case "la":
            matchedCity = CityInfo(cityName: "Los Angeles Area")
            zones = Self.sampleZones_LA()
        default:
            matchedCity = nil
            zones = []
        }
    }

    /// Returns realistic restrictions near the given coordinate using the preloaded dataset.
    /// If multiple zones cover the point, the restrictions are unioned.
    func restrictionsNear(_ coordinate: CLLocationCoordinate2D) async -> [CityRestriction] {
        guard !zones.isEmpty else { return [] }
        var results: [CityRestriction] = []
        for z in zones {
            let d = Self.distanceMeters(from: coordinate, to: z.center)
            if d <= z.radiusMeters {
                results.append(contentsOf: z.restrictions)
            }
        }
        // Deduplicate by (type, days, start, end, notes)
        var seen = Set<String>()
        let unique = results.filter { r in
            let key = "\(r.type.rawValue)|\(r.daysOfWeek.sorted())|\(r.startTime)|\(r.endTime)|\(r.notes ?? "")"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
        return unique
    }

    /// Returns simple circular overlays for the matched city's sample zones near the coordinate.
    func overlaysNear(_ coordinate: CLLocationCoordinate2D) async -> [ZoneOverlay] {
        await bootstrapIfNeeded(currentLocation: coordinate)
        return zones.map { ZoneOverlay(name: $0.name, center: $0.center, radiusMeters: $0.radiusMeters) }
    }

    // MARK: - City Detection Helpers

    private static func isInSanFrancisco(_ c: CLLocationCoordinate2D) -> Bool {
        // Rough SF bounding box
        return (37.60 ... 37.90).contains(c.latitude) && (-122.55 ... -122.30).contains(c.longitude)
    }

    private static func isInNewYorkCity(_ c: CLLocationCoordinate2D) -> Bool {
        // Rough Manhattan/NYC core bounding box
        return (40.60 ... 40.90).contains(c.latitude) && (-74.05 ... -73.85).contains(c.longitude)
    }

    private static func isInLosAngelesArea(_ c: CLLocationCoordinate2D) -> Bool {
        // Rough LA basin / South Bay bounding box (includes Hawthorne)
        return (33.65 ... 34.35).contains(c.latitude) && (-118.70 ... -118.00).contains(c.longitude)
    }

    // MARK: - Sample Datasets

    private static func sampleZones_SF() -> [CityZone] {
        // Common patterns: Street cleaning Tue/Thu mornings, rush-hour no-parking, metered during business hours
        let civicCenter = CityZone(
            name: "Civic Center",
            center: CLLocationCoordinate2D(latitude: 37.7793, longitude: -122.4193),
            radiusMeters: 800,
            restrictions: [
                CityRestriction(type: .streetCleaning, daysOfWeek: [2], startTime: "08:00", endTime: "10:00", notes: "Street cleaning (Tue)"),
                CityRestriction(type: .streetCleaning, daysOfWeek: [4], startTime: "08:00", endTime: "10:00", notes: "Street cleaning (Thu)"),
                CityRestriction(type: .noParking, daysOfWeek: [1,2,3,4,5], startTime: "07:00", endTime: "09:00", notes: "Tow-away lane (AM peak)"),
                CityRestriction(type: .metered, daysOfWeek: [1,2,3,4,5,6], startTime: "09:00", endTime: "18:00", notes: "Metered parking")
            ]
        )

        let mission = CityZone(
            name: "Mission",
            center: CLLocationCoordinate2D(latitude: 37.7599, longitude: -122.4148),
            radiusMeters: 1000,
            restrictions: [
                CityRestriction(type: .streetCleaning, daysOfWeek: [1], startTime: "09:00", endTime: "11:00", notes: "Street cleaning (Mon)"),
                CityRestriction(type: .streetCleaning, daysOfWeek: [4], startTime: "09:00", endTime: "11:00", notes: "Street cleaning (Thu)"),
                CityRestriction(type: .metered, daysOfWeek: [1,2,3,4,5,6], startTime: "09:00", endTime: "18:00", notes: "Metered parking")
            ]
        )

        let soma = CityZone(
            name: "SoMa",
            center: CLLocationCoordinate2D(latitude: 37.7786, longitude: -122.4059),
            radiusMeters: 900,
            restrictions: [
                CityRestriction(type: .streetCleaning, daysOfWeek: [3], startTime: "08:00", endTime: "10:00", notes: "Street cleaning (Wed)"),
                CityRestriction(type: .noParking, daysOfWeek: [1,2,3,4,5], startTime: "16:00", endTime: "18:00", notes: "Tow-away lane (PM peak)"),
                CityRestriction(type: .metered, daysOfWeek: [1,2,3,4,5,6], startTime: "09:00", endTime: "18:00", notes: "Metered parking")
            ]
        )

        let sunset = CityZone(
            name: "Inner Sunset",
            center: CLLocationCoordinate2D(latitude: 37.7530, longitude: -122.4860),
            radiusMeters: 1200,
            restrictions: [
                CityRestriction(type: .streetCleaning, daysOfWeek: [1], startTime: "09:00", endTime: "11:00", notes: "Street cleaning (Mon)"),
                CityRestriction(type: .streetCleaning, daysOfWeek: [4], startTime: "09:00", endTime: "11:00", notes: "Street cleaning (Thu)")
            ]
        )

        return [civicCenter, mission, soma, sunset]
    }

    private static func sampleZones_NYC() -> [CityZone] {
        // NYC alternate-side parking examples and rush hour lanes
        let uws = CityZone(
            name: "Upper West Side",
            center: CLLocationCoordinate2D(latitude: 40.7870, longitude: -73.9754),
            radiusMeters: 1200,
            restrictions: [
                CityRestriction(type: .streetCleaning, daysOfWeek: [1], startTime: "11:00", endTime: "12:30", notes: "ASP (Mon)"),
                CityRestriction(type: .streetCleaning, daysOfWeek: [4], startTime: "11:00", endTime: "12:30", notes: "ASP (Thu)"),
                CityRestriction(type: .noParking, daysOfWeek: [1,2,3,4,5], startTime: "07:00", endTime: "10:00", notes: "No standing (AM peak)")
            ]
        )

        let les = CityZone(
            name: "Lower East Side",
            center: CLLocationCoordinate2D(latitude: 40.7170, longitude: -73.9890),
            radiusMeters: 1000,
            restrictions: [
                CityRestriction(type: .streetCleaning, daysOfWeek: [2], startTime: "11:00", endTime: "12:30", notes: "ASP (Tue)"),
                CityRestriction(type: .streetCleaning, daysOfWeek: [5], startTime: "11:00", endTime: "12:30", notes: "ASP (Fri)")
            ]
        )

        let midtown = CityZone(
            name: "Midtown",
            center: CLLocationCoordinate2D(latitude: 40.7549, longitude: -73.9840),
            radiusMeters: 1000,
            restrictions: [
                CityRestriction(type: .noParking, daysOfWeek: [1,2,3,4,5], startTime: "16:00", endTime: "19:00", notes: "No standing (PM peak)"),
                CityRestriction(type: .metered, daysOfWeek: [1,2,3,4,5,6], startTime: "09:00", endTime: "19:00", notes: "Metered parking")
            ]
        )

        return [uws, les, midtown]
    }

    private static func sampleZones_LA() -> [CityZone] {
        // Sample zones around Hawthorne / Inglewood / LAX with plausible restrictions
        let hawthorne = CityZone(
            name: "Hawthorne Downtown",
            center: CLLocationCoordinate2D(latitude: 33.9164, longitude: -118.3526),
            radiusMeters: 1500,
            restrictions: [
                CityRestriction(type: .streetCleaning, daysOfWeek: [2], startTime: "08:00", endTime: "10:00", notes: "Street cleaning (Tue)"),
                CityRestriction(type: .streetCleaning, daysOfWeek: [5], startTime: "08:00", endTime: "10:00", notes: "Street cleaning (Fri)"),
                CityRestriction(type: .metered, daysOfWeek: [1,2,3,4,5,6], startTime: "09:00", endTime: "18:00", notes: "Metered parking (select blocks)")
            ]
        )

        let inglewood = CityZone(
            name: "Inglewood",
            center: CLLocationCoordinate2D(latitude: 33.9617, longitude: -118.3531),
            radiusMeters: 1500,
            restrictions: [
                CityRestriction(type: .streetCleaning, daysOfWeek: [1], startTime: "08:00", endTime: "10:00", notes: "Street cleaning (Mon)"),
                CityRestriction(type: .streetCleaning, daysOfWeek: [4], startTime: "08:00", endTime: "10:00", notes: "Street cleaning (Thu)"),
                CityRestriction(type: .noParking, daysOfWeek: [1,2,3,4,5], startTime: "07:00", endTime: "09:00", notes: "Tow-away lane (AM peak)")
            ]
        )

        let westchester = CityZone(
            name: "Westchester / LAX",
            center: CLLocationCoordinate2D(latitude: 33.9456, longitude: -118.4085),
            radiusMeters: 1600,
            restrictions: [
                CityRestriction(type: .noParking, daysOfWeek: [1,2,3,4,5], startTime: "16:00", endTime: "19:00", notes: "Tow-away lane (PM peak)"),
                CityRestriction(type: .permit, daysOfWeek: [1,2,3,4,5], startTime: "08:00", endTime: "17:00", notes: "Residential permit only (select streets)")
            ]
        )

        return [hawthorne, inglewood, westchester]
    }

    // MARK: - Utilities

    private static func distanceMeters(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let ca = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let cb = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return ca.distance(from: cb)
    }
}

