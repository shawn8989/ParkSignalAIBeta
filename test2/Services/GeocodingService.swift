// GeocodingService.swift
import Foundation
import CoreLocation

actor GeocodingService {
    private let geocoder = CLGeocoder()

    func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> String {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        // Prevent overlapping requests
        if geocoder.isGeocoding {
            geocoder.cancelGeocode()
        }

        do {
            let placemarks: [CLPlacemark]
            if #available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, visionOS 1.0, *) {
                placemarks = try await geocoder.reverseGeocodeLocation(location)
            } else {
                placemarks = await withCheckedContinuation { continuation in
                    geocoder.reverseGeocodeLocation(location) { placemarks, _ in
                        continuation.resume(returning: placemarks ?? [])
                    }
                }
            }
            guard let placemark = placemarks.first else { return "" }
            return Self.format(placemark)
        } catch {
            return ""
        }
    }

    private static func format(_ placemark: CLPlacemark) -> String {
        var streetParts: [String] = []
        if let subThoroughfare = placemark.subThoroughfare { streetParts.append(subThoroughfare) }
        if let thoroughfare = placemark.thoroughfare { streetParts.append(thoroughfare) }
        let street = streetParts.joined(separator: " ")

        var components: [String] = []
        if !street.isEmpty { components.append(street) }
        if let locality = placemark.locality { components.append(locality) }
        if let administrativeArea = placemark.administrativeArea { components.append(administrativeArea) }
        return components.joined(separator: ", ")
    }
}
