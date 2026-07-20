// HomeView (Dashboard)
// - Focuses on current parking tasks and spot management.
// - Removes user-facing session history previews; sessions are internal.
// - Keeps scans preview optional via Settings, but no Sessions/History link.

import SwiftUI
import MapKit
import CoreLocation
import SwiftData

struct DashboardView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.modelContext) private var context
    @StateObject private var dataProvider = ParkingDataProvider.shared

    // Fetch persisted spots
    @Query private var spots: [ParkingSpot]
    @Query private var scans: [SignScan]

    // Location
    @StateObject private var locationManager = LocationManager()
    @State private var showingOrientationPrompt = false
    @State private var tempOrientation: String = "with"
    @State private var showingLocationAlert = false
    @State private var locationAlertMessage = ""

    // Map camera and pin handling
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    )
    @State private var lastCameraCenter: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    @State private var pendingCoordinate: CLLocationCoordinate2D? // for new pin
    @State private var didAutoCenterOnce = false

    // Programmatic navigation when selecting from the map or list button
    @State private var selectedSpot: ParkingSpot?
    @State private var editingSpot: ParkingSpot?

    // Seed guard and geocoder
    @State private var hasSeeded = false
    private let geocoder = GeocodingService()

    // Settings
    @State private var showSettings = false
    @AppStorage("alertLeadMinutes") private var leadMinutes: Int = 15

    // Scan sheets
    @State private var showQuickScan = false
    @State private var showLiveScanner = false
    @State private var liveScanResult: String = ""
    @State private var showLiveResultSheet = false

    var body: some View {
        NavigationStack {
            VStack {
                ZStack(alignment: .bottomTrailing) {
                    MapView(
                        spots: spots,
                        userCoordinate: locationManager.lastLocation?.coordinate,
                        cameraPosition: $cameraPosition,
                        tempPin: pendingCoordinate,
                        onAddPinAtCoordinate: { coord in
                            // User double‑tapped on map: stage a new pin and ask for orientation
                            pendingCoordinate = coord
                            tempOrientation = "with"
                            showingOrientationPrompt = true
                        },
                        onSelectSpot: { spot in
                            // Tap a pin to open its details
                            selectedSpot = spot
                        }
                    )

                    // Floating "center on my location" button
                    Button(action: centerOnUserButtonTapped) {
                        Image(systemName: "location.circle.fill")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .padding(10)
                            .background(.thinMaterial)
                            .clipShape(Circle())
                            .shadow(radius: 3)
                    }
                    .accessibilityLabel("Center on My Location")
                    .padding(12)
                }
                .frame(height: 300)

                if let city = dataProvider.matchedCity {
                    Text("City Data Active: \(city.cityName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                }

                if let status = currentCurbStatus() {
                    HStack(spacing: 10) {
                        Image(systemName: status.iconName)
                            .foregroundStyle(status.color)
                        Text("My Curb Signal: \(status.label)")
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(status.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Avoid `if let` binding inside ViewBuilder for older compilers
                if locationManager.errorMessage != nil {
                    Text(locationManager.errorMessage!)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                List {
                    if !scans.isEmpty && UserDefaults.standard.bool(forKey: "showScansOnDashboard") {
                        Section(header: Text("Street Sign Scans")) {
                            NavigationLink {
                                ScansView()
                            } label: {
                                HStack {
                                    Image(systemName: "text.viewfinder")
                                    Text("Manage Scans (") + Text("\(scans.count)") + Text(")")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    if spots.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No spots yet")
                                .font(.headline)
                            Text("Add one by double‑tapping on the map or using \"Save Current Spot\" in the Add menu.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }

                    ForEach(spots, id: \.id) { spot in
                        HStack {
                            // Single tap opens details (intuitive)
                            Button {
                                selectedSpot = spot
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(spot.location)
                                        .font(.headline)
                                    Text("\(spot.restrictions.count) restriction(s)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)

                                    let status = ParkingSignalEvaluator.status(for: spot, now: Date(), leadMinutes: leadMinutes)
                                    signalBadge(for: status)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            // Visible quick action to center the map on this spot
                            Button {
                                centerOnSpot(spot)
                            } label: {
                                Image(systemName: "mappin.and.ellipse")
                                    .imageScale(.medium)
                                    .padding(8)
                                    .background(.thinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.borderless) // avoid triggering the row button
                            .accessibilityLabel("Show on Map")

                            // Edit button
                            Button {
                                editingSpot = spot
                            } label: {
                                Image(systemName: "pencil")
                                    .imageScale(.medium)
                                    .padding(8)
                                    .background(.thinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Edit Spot")
                        }
                        // Extra ways to access “Show on Map”
                        .contextMenu {
                            Button {
                                centerOnSpot(spot)
                            } label: {
                                Label("Show on Map", systemImage: "mappin.and.ellipse")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                centerOnSpot(spot)
                            } label: {
                                Label("Show on Map", systemImage: "mappin.and.ellipse")
                            }
                            .tint(.accentColor)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                context.delete(spot)
                                try? context.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                editingSpot = spot
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    .onDelete(perform: deleteSpots)
                }
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button {
                            handleSaveCurrentSpotTapped()
                        } label: {
                            Label("Save Current Spot", systemImage: "mappin.and.ellipse")
                        }
                        Button {
                            // Clear any temporary pin
                            pendingCoordinate = nil
                        } label: {
                            Label("Clear Temp Pin", systemImage: "xmark.circle")
                        }
                        .disabled(pendingCoordinate == nil)
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }

                // New Scan menu: Quick Scan (photo OCR) only
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showQuickScan = true
                        } label: {
                            Label("Quick Scan (Photo OCR)", systemImage: "text.viewfinder")
                        }
                    } label: {
                        Label("Scan", systemImage: "viewfinder")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: AlarmListView()) {
                        Label("Alarms", systemImage: "alarm")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if auth.isAuthenticated {
                        Button("Logout") { auth.logout() }
                    } else if auth.isGuest {
                        Button("Exit Guest") { auth.exitGuest() }
                    }
                }
            }
            .onAppear {
                // Seed data if needed
                seedIfNeeded()

                // Request permission and start location updates
                if locationManager.authorizationStatus == .notDetermined {
                    locationManager.requestWhenInUseAuthorization()
                } else if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                    locationManager.startUpdatingLocation()
                }

                // If we already have a user location on first appear, center on it
                if let c = locationManager.lastLocation?.coordinate {
                    setCamera(to: c, span: 0.02)
                    didAutoCenterOnce = true
                    Task { await dataProvider.bootstrapIfNeeded(currentLocation: c) }
                }
            }
            .onDisappear {
                locationManager.stopUpdatingLocation()
            }
            .onChange(of: locationManager.authorizationStatus) { newValue in
                if newValue == .authorizedWhenInUse || newValue == .authorizedAlways {
                    locationManager.startUpdatingLocation()
                }
            }
            // Optionally auto-center once when we first get a location
            .onChange(of: EquatableCoordinate(locationManager.lastLocation?.coordinate)) { coord in
                guard let lat = coord.latitude, let lon = coord.longitude else { return }
                let target = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                maybeAutoCenter(to: target)
                Task { await dataProvider.bootstrapIfNeeded(currentLocation: target) }
            }
            .alert("Cannot Save Spot", isPresented: $showingLocationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(locationAlertMessage)
            }
            .sheet(isPresented: $showingOrientationPrompt) {
                OrientationPromptView(orientation: $tempOrientation) {
                    if let coord = pendingCoordinate {
                        createSpot(at: coord, streetSide: DrivingSide.storedSide(from: tempOrientation))
                        pendingCoordinate = nil
                    } else {
                        createSpotFromCurrentLocation(streetSide: DrivingSide.storedSide(from: tempOrientation))
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showQuickScan) {
                QuickScanSheet()
            }
            .sheet(isPresented: $showLiveResultSheet) {
                QuickTextResultView(text: liveScanResult)
            }
            .sheet(item: $editingSpot) { spot in
                SpotEditView(spot: spot)
                    .environment(\.modelContext, context)
            }
            .navigationDestination(item: $selectedSpot) { spot in
                ParkingSpotDetailView(spot: spot, onUpdate: { _ in })
                    .environmentObject(auth)
            }
        }
    }

    private func seedIfNeeded() {
        guard !hasSeeded else { return }
        if spots.isEmpty {
            for spot in MockData.parkingSpots {
                context.insert(spot)
            }
            do {
                try context.save()
            } catch {
                print("HomeView: Failed to seed mock data: \(error)")
                print("HomeView: Existing spots count after seed attempt: \(spots.count)")
            }
        }
        hasSeeded = true
    }

    private func handleSaveCurrentSpotTapped() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            guard let loc = locationManager.lastLocation else {
                locationAlertMessage = "Current location not available yet. Please wait a moment and try again."
                showingLocationAlert = true
                return
            }
            // Pre-fill orientation with default "with"
            tempOrientation = "with"
            pendingCoordinate = nil // explicitly saving current location, not a map pin
            showingOrientationPrompt = true
        case .denied, .restricted:
            locationAlertMessage = "Location access is denied. Enable it in Settings to save your spot."
            showingLocationAlert = true
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        @unknown default:
            locationAlertMessage = "Unknown location authorization state."
            showingLocationAlert = true
        }
    }

    private func createSpotFromCurrentLocation(streetSide: String) {
        guard let loc = locationManager.lastLocation else { return }
        let coordinate = loc.coordinate
        createSpot(at: coordinate, streetSide: streetSide)
    }

    private func createSpot(at coordinate: CLLocationCoordinate2D, streetSide: String) {
        Task { @MainActor in
            // Reverse geocode for a human-readable label, with a fallback
            let address = await geocoder.reverseGeocode(coordinate: coordinate)
            let locationLabel = address.isEmpty
                ? String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
                : address

            let newSpot = ParkingSpot(
                location: locationLabel,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                streetSide: streetSide,
                restrictions: []
            )

            context.insert(newSpot)
            do {
                try context.save()
                print("HomeView: Saved spot id=\(newSpot.id) location=\(newSpot.location)")
                // Center on the newly created spot
                centerOnSpot(newSpot)
                selectedSpot = newSpot
            } catch {
                print("HomeView: Failed to save spot: \(error)")
                locationAlertMessage = "Failed to save spot: \(error.localizedDescription)"
                showingLocationAlert = true
            }
        }
    }

    // Placeholder street-side guesser; can be replaced later with compass or map geometry.
    private func guessStreetSide(from location: CLLocation) -> String? { return nil }

    private func centerOnSpot(_ spot: ParkingSpot) {
        let coord = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
        setCamera(to: coord, span: 0.01)
    }

    private func setCamera(to coordinate: CLLocationCoordinate2D, span: CLLocationDegrees) {
        withAnimation(.easeInOut) {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
                )
            )
            self.lastCameraCenter = coordinate
        }
    }

    // Auto-center only once when we first get a valid user location.
    private func maybeAutoCenter(to coordinate: CLLocationCoordinate2D) {
        guard !didAutoCenterOnce else { return }
        setCamera(to: coordinate, span: 0.02)
        didAutoCenterOnce = true
    }

    // MARK: - Delete helpers

    private func deleteSpots(at offsets: IndexSet) {
        let targets = offsets.map { spots[$0] }
        for spot in targets {
            context.delete(spot)
        }
        do {
            try context.save()
        } catch {
            locationAlertMessage = "Failed to delete spot(s): \(error.localizedDescription)"
            showingLocationAlert = true
        }
    }

    // Handler for the floating "center on my location" button
    private func centerOnUserButtonTapped() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if let coord = locationManager.lastLocation?.coordinate {
                setCamera(to: coord, span: 0.02)
            } else {
                locationAlertMessage = "Current location not available yet. Please wait a moment and try again."
                showingLocationAlert = true
            }
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            locationAlertMessage = "Location access is denied. Enable it in Settings to center on your location."
            showingLocationAlert = true
        @unknown default:
            locationAlertMessage = "Unknown location authorization state."
            showingLocationAlert = true
        }
    }

    private func signalBadge(for status: ParkingSignalStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status.iconName)
            Text(status.label)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.12))
        .foregroundStyle(status.color)
        .clipShape(Capsule())
    }
    
    private func currentCurbStatus() -> ParkingSignalStatus? {
        guard let coord = locationManager.lastLocation?.coordinate else { return nil }
        // Determine user side by the nearest spot's stored street side (minimal heuristic)
        let nearestSide = nearestSpotSide(to: coord)
        let sideEnum = nearestSide.flatMap { StreetSide(rawValue: $0.lowercased()) }
        return ParkingSignalEvaluator.statusForUserLocation(coord, userSide: sideEnum, scans: scans, now: Date(), leadMinutes: leadMinutes)
    }

    private func nearestSpotSide(to coordinate: CLLocationCoordinate2D) -> String? {
        guard !spots.isEmpty else { return nil }
        func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
            let R = 6_371_000.0
            let lat1 = a.latitude * .pi / 180
            let lon1 = a.longitude * .pi / 180
            let lat2 = b.latitude * .pi / 180
            let lon2 = b.longitude * .pi / 180
            let dlat = lat2 - lat1
            let dlon = lon2 - lon1
            let aa = sin(dlat/2) * sin(dlat/2) + cos(lat1) * cos(lat2) * sin(dlon/2) * sin(dlon/2)
            let c = 2 * atan2(sqrt(aa), sqrt(1-aa))
            return R * c
        }
        var best: (ParkingSpot, Double)? = nil
        for s in spots {
            let d = distance(coordinate, CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude))
            if best == nil || d < best!.1 { best = (s, d) }
        }
        return best?.0.streetSide
    }
}

private struct EquatableCoordinate: Equatable {
    let latitude: CLLocationDegrees?
    let longitude: CLLocationDegrees?

    init(_ coordinate: CLLocationCoordinate2D?) {
        self.latitude = coordinate?.latitude
        self.longitude = coordinate?.longitude
    }
}

private struct OrientationPromptView: View {
    @Binding var orientation: String // "with" or "against"
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Orientation", selection: $orientation) {
                    Text("With Traffic").tag("with")
                    Text("Against Traffic").tag("against")
                }
                .pickerStyle(.segmented)
            }
            .navigationTitle("Parking Orientation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onConfirm()
                        dismiss()
                    }
                }
            }
        }
    }
}

// Simple viewer for recognized text (from live scanner), with Copy action and analysis buttons.
private struct QuickTextResultView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    @State private var analysisOutput: String = ""
    @State private var isAnalyzing: Bool = false

    @State private var debugRequest: String = ""
    @State private var debugResponse: String = ""
    @State private var debugHTTPStatus: Int = 0
    @State private var showDebug: Bool = false

    private let aiService = AIAnalyzerService()
    private let localParser = ParkingTextParser()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ScrollView {
                    Text(text.isEmpty ? "No text detected." : text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }

                if isAnalyzing {
                    HStack {
                        ProgressView()
                        Text("Analyzing…")
                    }
                    .padding(.horizontal)
                }

                if !analysisOutput.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Analysis Result")
                            .font(.headline)
                        ScrollView {
                            Text(analysisOutput)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 200)
                    }
                    .padding(.horizontal)
                }

                if !analysisOutput.isEmpty || !debugRequest.isEmpty {
                    Toggle(isOn: $showDebug.animation()) {
                        Label("Show Debug Details", systemImage: "ladybug")
                    }
                    .padding(.horizontal)
                }

                if showDebug {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Debug (HTTP \(debugHTTPStatus))")
                            .font(.headline)
                        Text("Request JSON:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        ScrollView { Text(debugRequest).font(.footnote.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8) }
                            .frame(maxHeight: 160)
                        Text("Raw Response:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        ScrollView { Text(debugResponse).font(.footnote.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8) }
                            .frame(maxHeight: 200)
                    }
                    .padding(.horizontal)
                }

                HStack(spacing: 8) {
                    Button {
                        UIPasteboard.general.string = text
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Button("Analyze (Local)") {
                        Task { await analyzeLocal() }
                    }
                    .buttonStyle(.bordered)

                    Button("Analyze (AI)") {
                        Task { await analyzeAI() }
                    }
                    .buttonStyle(.bordered)

                    Button("Done") { dismiss() }
                        .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("Scan Result")
        }
    }

    @MainActor
    private func analyzeAI() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let result = try await aiService.analyzeWithDebug(ocrText: trimmed)
            analysisOutput = result.rawJSON
            debugRequest = result.requestJSON
            debugResponse = result.responseBody
            debugHTTPStatus = result.httpStatus
        } catch {
            // Fallback to local parsing on failure
            await analyzeLocal()
        }
    }

    @MainActor
    private func analyzeLocal() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let local = localParser.analyze(ocrText: trimmed)
        if let data = try? JSONEncoder().encode(local), let s = String(data: data, encoding: .utf8) {
            analysisOutput = s
        } else {
            analysisOutput = String(describing: local)
        }
    }
}

