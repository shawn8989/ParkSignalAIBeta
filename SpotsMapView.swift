import UIKit
import SwiftUI
import MapKit
import CoreLocation
import SwiftData

struct SpotsMapView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.modelContext) private var context
    @Query private var spots: [ParkingSpot]
    @Query private var cars: [Car]
    @Query private var sessions: [ParkSession]
    
    @StateObject private var locationManager = LocationManager()
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    )
    @State private var selectedSpot: ParkingSpot?
    @State private var didAutoCenterOnce = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var lastUsedCarID: UUID? = nil
    
    @State private var pendingCoordinate: CLLocationCoordinate2D? = nil
    @State private var showNewSpotPrompt: Bool = false
    @State private var newSpotLabel: String = ""
    @State private var newSpotOrientation: String = "with"
    @State private var carPendingPark: Car? = nil
    @State private var eligibility: ParkingEligibility? = nil
    @State private var isCheckingEligibility = false
    @State private var showEligibilityConfirm = false
    @State private var confirmCoord: CLLocationCoordinate2D? = nil
    @State private var confirmCar: Car? = nil

    @State private var isShowingFilters: Bool = false
    @State private var showOnlyAllowedNow: Bool = false
    @State private var showSoonRestrictions: Bool = true
    @State private var showParkedSpots: Bool = true
    
    @AppStorage("map.showAvailabilityOverlay") private var mapShowAvailabilityOverlay: Bool = true
    @AppStorage("map.showLegend") private var mapShowLegend: Bool = true
    @AppStorage("map.showCityZoneOverlay") private var mapShowCityZoneOverlay: Bool = true
    
    private let geocoder = GeocodingService()
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                MapView(
                    spots: filteredSpots(),
                    userCoordinate: locationManager.lastLocation?.coordinate,
                    cameraPosition: $cameraPosition,
                    tempPin: pendingCoordinate,
                    onAddPinAtCoordinate: { coord in
                        Task { @MainActor in
                            let address = await geocoder.reverseGeocode(coordinate: coord)
                            pendingCoordinate = coord
                            newSpotLabel = address.isEmpty ? "Address unavailable" : address
                            newSpotOrientation = "with"
                            carPendingPark = nil
                            showNewSpotPrompt = true
                        }
                    },
                    onSelectSpot: { spot in selectedSpot = spot }
                    , showAvailabilityOverlay: mapShowAvailabilityOverlay
                    , showLegend: mapShowLegend
                    , showCityZoneOverlay: mapShowCityZoneOverlay
                )
                Button(action: {
                    let gen = UIImpactFeedbackGenerator(style: .light)
                    gen.impactOccurred()
                    parkHere()
                }) {
                    Label("Park Here", systemImage: "mappin.and.ellipse")
                        .padding(10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding()
            }
            .navigationTitle("Map")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingFilters.toggle()
                    } label: {
                        Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .alert("Park Here", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                switch locationManager.authorizationStatus {
                case .notDetermined:
                    locationManager.requestWhenInUseAuthorization()
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
                if let s = UserDefaults.standard.string(forKey: "CarList.LastUsedCarID"), let id = UUID(uuidString: s) {
                    lastUsedCarID = id
                }
            }
            .onDisappear {
                locationManager.stopUpdatingLocation()
            }
            .navigationDestination(item: $selectedSpot) { spot in
                ParkingSpotDetailView(spot: spot, onUpdate: { _ in })
                    .environmentObject(auth)
            }
            .sheet(isPresented: $showNewSpotPrompt) {
                NavigationStack {
                    Form {
                        Section("Location") {
                            TextField("Label", text: $newSpotLabel)
                        }
                        Section("Details") {
                            Picker("Orientation", selection: $newSpotOrientation) {
                                Text("With Traffic").tag("with")
                                Text("Against Traffic").tag("against")
                            }
                        }
                        Section("Car") {
                            Picker("Car", selection: Binding<UUID?>(
                                get: { carPendingPark?.id },
                                set: { newID in carPendingPark = cars.first(where: { $0.id == newID }) }
                            )) {
                                ForEach(cars, id: \.id) { car in
                                    Text(car.nickname).tag(Optional(car.id))
                                }
                            }
                        }
                        Section("Eligibility") {
                            Button {
                                Task { await testEligibility() }
                            } label: {
                                Label(isCheckingEligibility ? "Testing…" : "Test Parking Eligibility", systemImage: "checkmark.shield")
                            }
                            .disabled(pendingCoordinate == nil || isCheckingEligibility)

                            if let e = eligibility {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: e.allowed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                            .foregroundColor(e.allowed ? .green : .yellow)
                                        Text(e.summary).font(.subheadline)
                                    }
                                    if !e.warnings.isEmpty {
                                        ForEach(e.warnings, id: \.self) { w in
                                            Text("• \(w)").font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                    if let n = e.nextRestriction {
                                        Text("Next restriction: \(n.formatted(date: .omitted, time: .shortened))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Save Spot")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showNewSpotPrompt = false; carPendingPark = nil; pendingCoordinate = nil }
                        }
                        ToolbarItemGroup(placement: .confirmationAction) {
                            Button("Save Spot") {
                                if let coord = pendingCoordinate {
                                    let storedSide = DrivingSide.storedSide(from: newSpotOrientation)
                                    let label = newSpotLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let finalLabel = label.isEmpty ? "Address unavailable" : label
                                    let newSpot = ParkingSpot(location: finalLabel, latitude: coord.latitude, longitude: coord.longitude, streetSide: storedSide, restrictions: [])
                                    context.insert(newSpot)
                                    do { try context.save() } catch { }
                                    showNewSpotPrompt = false
                                    carPendingPark = nil
                                    pendingCoordinate = nil
                                }
                            }
                            .disabled(pendingCoordinate == nil)

                            Button("Save & Park") {
                                Task { await saveAndParkWithEligibilityCheck() }
                            }
                            .disabled(pendingCoordinate == nil || carPendingPark == nil)
                        }
                    }
                    .confirmationDialog("Restriction active here", isPresented: $showEligibilityConfirm, titleVisibility: .visible) {
                        Button("Park Anyway", role: .destructive) {
                            proceedToSaveAndPark()
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text(eligibility?.summary ?? "Not recommended to park here now.")
                    }
                }
            }
            .sheet(isPresented: $isShowingFilters) {
                NavigationStack {
                    Form {
                        Toggle("Only Allowed Now", isOn: $showOnlyAllowedNow)
                        Toggle("Show Soon Restrictions", isOn: $showSoonRestrictions)
                        Toggle("Show Parked Spots", isOn: $showParkedSpots)
                        Toggle("Availability Overlays", isOn: $mapShowAvailabilityOverlay)
                        Toggle("City Zone Overlays", isOn: $mapShowCityZoneOverlay)
                        Toggle("Legend", isOn: $mapShowLegend)
                    }
                    .navigationTitle("Filters")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingFilters = false }
                        }
                    }
                }
            }
        }
    }
    
    private func parkHere() {
        guard let loc = locationManager.lastLocation else {
            alertMessage = "Current location not available."
            showAlert = true
            return
        }
        guard !cars.isEmpty else {
            alertMessage = "Add a car first from the Cars tab."
            showAlert = true
            return
        }
        let coordinate = loc.coordinate
        Task { @MainActor in
            let address = await geocoder.reverseGeocode(coordinate: coordinate)
            pendingCoordinate = coordinate
            newSpotLabel = address.isEmpty ? "Address unavailable" : address
            newSpotOrientation = "with"
            carPendingPark = nil // require user to pick a car explicitly
            showNewSpotPrompt = true
        }
    }

    @MainActor
    private func testEligibility() async {
        guard let coord = pendingCoordinate else { return }
        isCheckingEligibility = true
        defer { isCheckingEligibility = false }
        let result = await ParkingEligibilityEvaluator.evaluate(coordinate: coord, spotRestrictions: [])
        eligibility = result
    }

    @MainActor
    private func saveAndParkWithEligibilityCheck() async {
        guard let coord = pendingCoordinate, let car = carPendingPark else { return }
        isCheckingEligibility = true
        let result = await ParkingEligibilityEvaluator.evaluate(coordinate: coord, spotRestrictions: [])
        isCheckingEligibility = false
        if !result.allowed {
            eligibility = result
            confirmCoord = coord
            confirmCar = car
            showEligibilityConfirm = true
            return
        }
        // Allowed case: proceed directly
        confirmCoord = coord
        confirmCar = car
        proceedToSaveAndPark()
    }

    private func proceedToSaveAndPark() {
        guard let coord = confirmCoord, let car = confirmCar else { return }
        let storedSide = DrivingSide.storedSide(from: newSpotOrientation)
        let label = newSpotLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = label.isEmpty ? "Address unavailable" : label
        let newSpot = ParkingSpot(location: finalLabel, latitude: coord.latitude, longitude: coord.longitude, streetSide: storedSide, restrictions: [])
        context.insert(newSpot)
        do { try context.save() } catch { }

        // End any other active sessions for this car
        let now = Date()
        for s in sessions where s.car?.id == car.id && s.endedAt == nil { s.endedAt = now }
        let session = ParkSession(spot: newSpot, startedAt: now, endedAt: nil, car: car)
        context.insert(session)
        do { try context.save() } catch { }
        UserDefaults.standard.set(car.id.uuidString, forKey: "CarList.LastUsedCarID")
        alertMessage = "Parked \(car.nickname) at \(newSpot.location)."
        showAlert = true

        showNewSpotPrompt = false
        carPendingPark = nil
        pendingCoordinate = nil
        eligibility = nil
        confirmCoord = nil
        confirmCar = nil
        showEligibilityConfirm = false
    }

    private func isRestrictedNow(_ spot: ParkingSpot, now: Date = Date()) -> Bool {
        let cal = Calendar.current
        let weekday0_6 = (cal.component(.weekday, from: now) + 6) % 7
        for r in spot.restrictions {
            let days = r.daysOfWeek
            if !days.isEmpty && !days.contains(weekday0_6) { continue }
            let sh = cal.component(.hour, from: r.startTime)
            let sm = cal.component(.minute, from: r.startTime)
            let eh = cal.component(.hour, from: r.endTime)
            let em = cal.component(.minute, from: r.endTime)
            var start = todayAt(hour: sh, minute: sm, ref: now)
            var end = todayAt(hour: eh, minute: em, ref: now)
            if end <= start { end = end.addingTimeInterval(24*60*60) }
            if now >= start && now <= end {
                if r.type == .noParking || r.type == .streetCleaning { return true }
            }
        }
        return false
    }

    private func nextRestrictionDate(for spot: ParkingSpot, from now: Date = Date()) -> Date? {
        return spot.nextRestrictionDate(from: now)
    }
    
    private func todayAt(hour: Int, minute: Int, ref: Date) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: ref)
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return Calendar.current.date(from: comps) ?? ref
    }
    
    private func filteredSpots() -> [ParkingSpot] {
        var results = spots
        if showOnlyAllowedNow {
            results = results.filter { !isRestrictedNow($0) }
        }
        if !showSoonRestrictions {
            results = results.filter { $0.nextRestrictionDate()?.timeIntervalSinceNow ?? .infinity > 2 * 60 * 60 }
        }
        if !showParkedSpots {
            results = results.filter { !$0.isCurrentlyParked }
        }
        return results
    }
}
