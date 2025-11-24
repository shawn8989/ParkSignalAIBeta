import SwiftUI
import MapKit
import CoreLocation
import SwiftData

struct SpotsMapView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.modelContext) private var context
    @Query private var spots: [ParkingSpot]
    
    @StateObject private var locationManager = LocationManager()
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    )
    @State private var selectedSpot: ParkingSpot?
    @State private var didAutoCenterOnce = false
    
    var body: some View {
        NavigationStack {
            MapView(
                spots: spots,
                userCoordinate: locationManager.lastLocation?.coordinate,
                cameraPosition: $cameraPosition,
                tempPin: nil,
                onAddPinAtCoordinate: { _ in },
                onSelectSpot: { spot in selectedSpot = spot }
            )
            .navigationTitle("Map")
            .onAppear {
                switch locationManager.authorizationStatus {
                case .notDetermined:
                    locationManager.requestAuthorization()
                case .authorizedAlways, .authorizedWhenInUse:
                    locationManager.startUpdatingLocation()
                    if let coordinate = locationManager.lastLocation?.coordinate, !didAutoCenterOnce {
                        cameraPosition = .region(
                            MKCoordinateRegion(
                                center: coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                            )
                        )
                        didAutoCenterOnce = true
                    }
                default:
                    break
                }
            }
            .onDisappear {
                locationManager.stopUpdatingLocation()
            }
            .navigationDestination(item: $selectedSpot) { spot in
                ParkingSpotDetailView(spot: spot, onUpdate: { _ in })
                    .environmentObject(auth)
            }
        }
    }
}
