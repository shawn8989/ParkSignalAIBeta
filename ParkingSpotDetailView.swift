import SwiftUI

struct ParkingSpotDetailView: View {
    let spot: ParkingSpot
    
    var body: some View {
        List {
            Section(header: Text("Location")) {
                Text(spot.location)
            }
            Section(header: Text("Restrictions")) {
                ForEach(spot.restrictions, id: \.id) { restriction in
                    VStack(alignment: .leading) {
                        Text(restriction.type.displayName)
                            .font(.headline)
                        Text(restriction.timeDescription)
                        Text(restriction.daysDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Spot Details")
    }
}
