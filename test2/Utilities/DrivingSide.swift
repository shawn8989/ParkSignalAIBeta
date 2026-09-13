import Foundation

enum DrivingSide {
    // A minimal set of left-hand traffic regions. This list can be extended as needed.
    private static let leftHandTrafficRegions: Set<String> = [
        "GB", "IE", "AU", "NZ", "JP", "IN", "PK", "BD", "LK", "ZA", "NA", "BW",
        "LS", "SZ", "ZM", "ZW", "MU", "MY", "SG", "TH", "ID", "HK", "MO", "CY", "MT"
    ]

    /// Returns true if the current region drives on the right side of the road.
    static var isRightHandTraffic: Bool {
        let region = Locale.current.region?.identifier.uppercased() ?? "US"
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

    // MARK: - Address-parity side inference
    // US addresses put even house numbers on one side of the street and odd on the
    // other, so the address tells you which side you're on — no manual with/against
    // pick needed for a scanned (geocoded) spot.

    /// The leading house number of an address like "123 Main St, City, ST".
    static func houseNumber(from address: String?) -> Int? {
        guard let a = address?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty else { return nil }
        let firstToken = a.split(separator: " ").first.map(String.init) ?? ""
        let digits = String(firstToken.prefix { $0.isNumber })
        return Int(digits)
    }

    /// Infer the curb side from house-number parity. Returns "left"/"right" — a
    /// consistent label where the two parities always map to opposite sides (the
    /// absolute orientation isn't guaranteed without heading, but consistency is what
    /// spot-deduplication needs). Returns nil when there is no house number to read.
    static func side(fromAddress address: String?) -> String? {
        guard let n = houseNumber(from: address) else { return nil }
        return n % 2 == 0 ? "right" : "left"
    }

    /// A normalized street key for grouping signs on the same street: the
    /// thoroughfare only, with the house number, city, and state removed. So
    /// "120 Main St, SF, CA" and "148 Main St, SF, CA" share the key "main st".
    static func streetKey(from address: String?) -> String {
        guard let a = address?.lowercased() else { return "" }
        let firstComponent = a.split(separator: ",").first.map(String.init) ?? a
        let tokens = firstComponent.split(separator: " ").map(String.init)
        let dropLeadingNumber = (tokens.first.flatMap { Int($0.prefix { c in c.isNumber }) } != nil)
        let streetTokens = dropLeadingNumber ? Array(tokens.dropFirst()) : tokens
        return streetTokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
