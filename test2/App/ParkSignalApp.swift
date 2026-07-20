import SwiftUI
import SwiftData

@main
struct ParkSignalApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(for: [
            ParkingSpot.self,
            Restriction.self,
            SignScan.self,
            ParkSession.self
        ])
    }
}
