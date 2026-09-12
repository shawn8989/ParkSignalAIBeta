import Foundation

/// A stable, per-install identifier for the local user.
///
/// ParkSignal is a local-first single-user app (no accounts). Restrictions and
/// scans still carry a `sourceUser` UUID for provenance and possible future
/// sync; this provides that value without a login. The id is generated once and
/// persisted in `UserDefaults` for the life of the install.
enum LocalIdentity {
    private static let key = "com.SOTech.ParkSignalAI.localUserID"

    static let userID: UUID = {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: key), let uuid = UUID(uuidString: stored) {
            return uuid
        }
        let new = UUID()
        defaults.set(new.uuidString, forKey: key)
        return new
    }()
}
