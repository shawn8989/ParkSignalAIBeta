import SwiftUI
import MapKit

struct MapView: View {
    var spots: [ParkingSpot]
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    
    var body: some View {
        Map(coordinateRegion: $region, annotationItems: spots) { spot in
            // NOTE: For MVP, using dummy coordinates for now; expand later
            MapMarker(coordinate: CLLocationCoordinate2D(latitude: 37.78, longitude: -122.42), tint: .accentColor)
        }
        .navigationTitle("Parking Map")
    }
}
