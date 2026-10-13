import CoreLocation
import Contacts

enum SpotLocationUtils {
    /// A short "name, city, state" label for a coordinate, or nil when geocoding fails.
    static func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> String? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if let p = placemarks.first {
                let parts = [p.name, p.locality, p.administrativeArea].compactMap { $0 }.filter { !$0.isEmpty }
                if !parts.isEmpty { return parts.joined(separator: ", ") }
                if let line = p.postalAddress?.street { return line }
            }
            return nil
        } catch {
            return nil
        }
    }
}
