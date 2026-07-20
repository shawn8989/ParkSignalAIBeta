import Foundation

enum DrivingSide {
    // A minimal set of left-hand traffic regions. This list can be extended as needed.
    private static let leftHandTrafficRegions: Set<String> = [
        "GB", "IE", "AU", "NZ", "JP", "IN", "PK", "BD", "LK", "ZA", "NA", "BW",
        "LS", "SZ", "ZM", "ZW", "MU", "MY", "SG", "TH", "ID", "HK", "MO", "CY", "MT"
    ]

    /// Returns true if the current region drives on the right side of the road.
    static var isRightHandTraffic: Bool {
        let region = Locale.current.region?.identifier.uppercased() ?? Locale.current.regionCode?.uppercased() ?? "US"
        return !leftHandTrafficRegions.contains(region)
    }

    /// Map a UI selection ("with" or "against") to a stored street side value ("left"/"right").
    /// - Parameter selection: "with" means with traffic; "against" means against traffic.
    /// - Returns: "left" or "right" depending on the region; defaults to "right" if unknown.
    static func storedSide(from selection: String) -> String {
        switch selection {
        case "with":
            return isRightHandTraffic ? "right" : "left"
        case "against":
            return isRightHandTraffic ? "left" : "right"
        default:
            return isRightHandTraffic ? "right" : "left"
        }
    }

    /// Map a stored street side ("left"/"right") back to a UI selection ("with"/"against").
    /// - Parameter stored: The stored spot.streetSide value.
    /// - Returns: "with" or "against".
    static func selection(from stored: String) -> String {
        let normalized = stored.lowercased()
        if isRightHandTraffic {
            return normalized == "right" ? "with" : "against"
        } else {
            return normalized == "left" ? "with" : "against"
        }
    }
}
