import SwiftUI
import SwiftData
import MapKit

extension ParkingSpot {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var signalStatus: ParkingSignalStatus {
        ParkingSignalEvaluator.status(for: self)
    }
}

struct MapTabView: View {
    @Query private var spots: [ParkingSpot]
    @State private var cameraPosition: MapCameraPosition = .userLocation(
        fallback: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        ))
    )
    @State private var selectedSpot: ParkingSpot?

    /// Spots at (0,0) were saved without a location fix; they'd all pile up in the Gulf of Guinea.
    private var mappableSpots: [ParkingSpot] {
        spots.filter { $0.latitude != 0 || $0.longitude != 0 }
    }

    var body: some View {
        NavigationStack {
            Map(position: $cameraPosition) {
                UserAnnotation()
                ForEach(mappableSpots) { spot in
                    Annotation(spot.location, coordinate: spot.coordinate) {
                        SpotPin(spot: spot)
                            .onTapGesture { selectedSpot = spot }
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedSpot) { spot in
                SpotDetailView(spot: spot)
            }
            .overlay {
                if mappableSpots.isEmpty {
                    ContentUnavailableView(
                        "No saved spots yet",
                        systemImage: "mappin.slash",
                        description: Text("Scan a parking sign and save it — it will show up here, colored by whether you can park.")
                    )
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(32)
                    .allowsHitTesting(false)
                }
            }
        }
    }
}

private struct SpotPin: View {
    let spot: ParkingSpot

    var body: some View {
        let status = spot.signalStatus
        ZStack {
            Circle()
                .fill(status.color.gradient)
                .frame(width: 34, height: 34)
                .shadow(radius: 2)
            Image(systemName: spot.activeSession != nil ? "car.fill" : status.iconName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}
