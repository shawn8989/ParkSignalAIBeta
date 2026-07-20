import Foundation

// Removed manual Hashable conformance for ParkingSpot.
// SwiftData's @Model macro provides the necessary identity and observation semantics.
// In SwiftUI, prefer `List(spots, id: \.id)` rather than making the model Hashable.
