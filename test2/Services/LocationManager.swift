import Foundation
import Combine
import CoreLocation

@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var lastLocation: CLLocation?
    @Published var errorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        // Seed with current status so the UI has a real value immediately.
        // Read from the real manager instance rather than allocating a
        // throwaway CLLocationManager.
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5 // meters
    }

    func requestWhenInUseAuthorization() {
        // Note: CLLocationManager.locationServicesEnabled() is a blocking
        // cross-process call and must not run on the main actor (iOS 26 flags
        // it as "unsafeForcedSync"). If services are disabled system-wide, the
        // request simply won't prompt and the delegate reports .denied/.restricted,
        // which is surfaced with a Settings hint below.
        manager.requestWhenInUseAuthorization()
    }

    // Call this to ensure we have permission and start updates if allowed.
    func ensureAuthorized() {
        // Developer safeguard: if the usage description key is missing, iOS will never prompt.
        if Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") == nil {
            errorMessage = "Missing NSLocationWhenInUseUsageDescription in Info.plist. The system cannot ask for location permission."
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            errorMessage = "Location permission denied. Enable it in Settings."
        @unknown default:
            errorMessage = "Unknown location authorization state."
        }
    }

    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                self.errorMessage = nil
                self.manager.startUpdatingLocation()
            case .denied, .restricted:
                self.errorMessage = "Location permission denied. Enable it in Settings to save your spot."
            case .notDetermined:
                self.errorMessage = nil
            @unknown default:
                self.errorMessage = "Unknown location authorization state."
            }
        }
    }

    // Kept for completeness/back-compat
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authorizationStatus = status
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                self.errorMessage = nil
                self.manager.startUpdatingLocation()
            case .denied, .restricted:
                self.errorMessage = "Location permission denied. Enable it in Settings to save your spot."
            case .notDetermined:
                self.errorMessage = nil
            @unknown default:
                self.errorMessage = "Unknown location authorization state."
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = loc
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if let cle = error as? CLError {
                switch cle.code {
                case .denied:
                    // Authorization changes are already handled in delegate callbacks; avoid noisy errors.
                    return
                case .locationUnknown:
                    // Transient; ignore.
                    return
                default:
                    break
                }
            }
            self.errorMessage = error.localizedDescription
        }
    }
}
