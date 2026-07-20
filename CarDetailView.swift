// CarDetailView
// - Centralizes parking session management via Car+Parking (start/end/toggle).
// - Uses NotificationManager for restriction alerts instead of ad-hoc per-view scheduling.
// - Avoids duplicating restriction timing logic; defer to ParkingSpot+Status where needed.
// - History/Sessions are not user-facing here; UI focuses on current parking state and quick actions.

import SwiftUI
import SwiftData
import CoreLocation
import UserNotifications

struct CarDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var car: Car

    @Query private var spots: [ParkingSpot]
    @Query private var sessions: [ParkSession]

    @StateObject private var locationManager = LocationManager()

    @State private var selectedSpotID: UUID? = nil
    @State private var showSpotPicker = false

    @State private var pendingCoordinate: CLLocationCoordinate2D? = nil
    @State private var showNewSpotPrompt = false
    @State private var newSpotLabel: String = ""
    @State private var newSpotOrientation: String = "with"

    private let geocoder = GeocodingService()

    var body: some View {
        NavigationStack {
            List {
                Section("Car") {
                    HStack(spacing: 12) {
                        Image(systemName: car.iconName)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(car.nickname).font(.headline)
                            if let plate = car.licensePlate, !plate.isEmpty {
                                Text(plate).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section("Parked Status") {
                    if let active = activeSession(), let spot = active.spot {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Parked at:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            NavigationLink {
                                ParkingSpotDetailView(spot: spot, onUpdate: { _ in })
                                    .environment(\.modelContext, context)
                            } label: {
                                HStack {
                                    Image(systemName: "parkingsign.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .green)
                                    Text(spot.location).lineLimit(1)
                                }
                            }
                        }
                        Button(role: .destructive) { unpark() } label: {
                            Label("Unpark", systemImage: "xmark.circle")
                        }
                    } else {
                        Text("Not parked")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Button { showSpotPicker = true } label: {
                            Label("Move to Spot", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Spacer()
                        Button { parkHere() } label: {
                            Label("Park Here (New Spot)", systemImage: "mappin.and.ellipse")
                        }
                    }
                }
            }
            .navigationTitle(car.nickname)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSpotPicker = true
                    } label: {
                        Label("Move", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            .onAppear {
                if locationManager.authorizationStatus == .notDetermined {
                    locationManager.requestWhenInUseAuthorization()
                } else if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                    locationManager.startUpdatingLocation()
                }
                if let active = activeSession()?.spot?.id {
                    selectedSpotID = active
                }
            }
            .onDisappear { locationManager.stopUpdatingLocation() }
            .sheet(isPresented: $showSpotPicker) {
                NavigationStack {
                    List {
                        ForEach(spots, id: \.id) { spot in
                            Button {
                                assign(to: spot)
                                showSpotPicker = false
                            } label: {
                                HStack {
                                    Image(systemName: "mappin.and.ellipse").foregroundStyle(.tint)
                                    VStack(alignment: .leading) {
                                        Text(spot.location).font(.headline)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Select Spot")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showSpotPicker = false } }
                    }
                }
            }
            .sheet(isPresented: $showNewSpotPrompt) {
                NavigationStack {
                    Form {
                        Section("Location") {
                            TextField("Label", text: $newSpotLabel)
                            Text(pendingCoordinate.map { String(format: "%.5f, %.5f", $0.latitude, $0.longitude) } ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Section("Details") {
                            Picker("Orientation", selection: $newSpotOrientation) {
                                Text("With Traffic").tag("with")
                                Text("Against Traffic").tag("against")
                            }
                        }
                    }
                    .navigationTitle("Save Spot")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showNewSpotPrompt = false; pendingCoordinate = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save & Park") {
                                if let coord = pendingCoordinate {
                                    let storedSide = DrivingSide.storedSide(from: newSpotOrientation)
                                    let label = newSpotLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let finalLabel = label.isEmpty ? String(format: "%.5f, %.5f", coord.latitude, coord.longitude) : label
                                    let newSpot = ParkingSpot(location: finalLabel, latitude: coord.latitude, longitude: coord.longitude, streetSide: storedSide, restrictions: [])
                                    context.insert(newSpot)
                                    do { try context.save() } catch { }
                                    assign(to: newSpot)
                                    showNewSpotPrompt = false
                                    pendingCoordinate = nil
                                }
                            }
                            .disabled(pendingCoordinate == nil)
                        }
                    }
                }
            }
        }
    }

    private func activeSession() -> ParkSession? {
        sessions.first(where: { $0.car?.id == car.id && $0.endedAt == nil })
    }

    private func unpark() {
        // End the active session for this car (if any) using the centralized API.
        // This ensures consistent behavior across the app (no duplicated loops/predicates).
        let previousSpot = activeSession()?.spot
        car.endCurrentParking(at: Date())
        try? context.save()

        // Best-effort: cancel any weekly notifications we may have scheduled for the previous spot.
        // (If none were scheduled, this is a harmless no-op.)
        if let s = previousSpot {
            Task { await NotificationManager.shared.cancel(for: s.restrictions, spot: s) }
        }
    }

    private func assign(to spot: ParkingSpot) {
        // Centralized session management: end any prior active session for this car and start a new one at this spot.
        let _ = car.startParking(at: spot, now: Date(), in: context)
        try? context.save()

        // Schedule restriction reminders for this spot using the NotificationManager (central policy/lead time).
        Task { await NotificationManager.shared.schedule(for: spot.restrictions, spot: spot) }
    }

    private func parkHere() {
        guard let loc = locationManager.lastLocation else { return }
        let coordinate = loc.coordinate
        Task { @MainActor in
            let address = await geocoder.reverseGeocode(coordinate: coordinate)
            pendingCoordinate = coordinate
            newSpotLabel = address.isEmpty ? String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude) : address
            newSpotOrientation = "with"
            showNewSpotPrompt = true
        }
    }
}
