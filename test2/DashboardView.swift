import SwiftUI
import MapKit

struct DashboardView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @State private var selectedSpot: ParkingSpot?
    @State private var spots: [ParkingSpot] = MockData.parkingSpots
    
    var body: some View {
        NavigationStack {
            VStack {
                // Map on top
                MapView(spots: spots)
                    .frame(height: 300)
                
                // List of spots below for navigation to details
                List(spots, id: \.id) { spot in
                    NavigationLink(value: spot) {
                        VStack(alignment: .leading) {
                            Text(spot.location)
                                .font(.headline)
                            Text("\(spot.restrictions.count) restriction(s)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .navigationDestination(for: ParkingSpot.self) { spot in
                    ParkingSpotDetailView(spot: spot, onUpdate: { updated in
                        if let idx = spots.firstIndex(where: { $0.id == updated.id }) {
                            spots[idx] = updated
                        }
                    })
                    .environmentObject(auth)
                }
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if auth.isAuthenticated {
                        Button("Logout") { auth.logout() }
                    } else if auth.isGuest {
                        Button("Exit Guest") { auth.exitGuest() }
                    }
                }
            }
        }
    }
}
