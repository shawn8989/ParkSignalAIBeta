import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import CoreLocation
import Contacts
import MapKit
import Combine

struct ParkingSpotDetailView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var spot: ParkingSpot
    var onUpdate: ((ParkingSpot) -> Void)?
    @State private var showAddRestriction = false
    @State private var newRestriction = Restriction(
        type: .noParking,
        startTime: Date(),
        endTime: Date(),
        daysOfWeek: [],
        sourceUser: UUID()
    )
    @State private var showEditSpot = false
    @State private var showCarPickerSheet = false
    @State private var cityRestrictions: [CityRestriction] = []
    @State private var loadingCityData = false
    @State private var cityDataError: String? = nil
    @State private var matchedCityName: String? = nil

    // Scan flow state
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var isAnalyzing = false
    @State private var ocrText: String = ""
    @State private var analysis: AIAnalysisResponse?
    @State private var showAnalysisSheet = false
    @State private var photoFilename: String?
    @State private var scanError: String?

    @State private var usedAIParsing: Bool? = nil
    @State private var aiFallbackReason: String? = nil

    @State private var showToast: Bool = false
    @State private var toastMessage: String? = nil
    @State private var showQuickReview: Bool = false
    @State private var pendingQuickImage: UIImage? = nil
    @State private var pendingQuickOCRText: String? = nil
    @State private var resolvedSavedScanAddress: String? = nil

    @State private var showMapSheet: Bool = false
    @State private var mapRegion: MKCoordinateRegion = MKCoordinateRegion()
    @State private var mapPinTitle: String? = nil
    @State private var mapPreviewRegion: MKCoordinateRegion = MKCoordinateRegion()
    @State private var mapPreviewPosition: MapCameraPosition = .automatic
    @State private var showDeleteAlert: Bool = false

    // Segment editing state
    @State private var segmentEditScan: SignScan? = nil

    private var lastScan: SignScan? {
        spot.signScans.sorted(by: { $0.createdAt > $1.createdAt }).first
    }

    @AppStorage("useAIParsing") private var useAIParsing: Bool = true
    @AppStorage("alertLeadMinutes") private var leadMinutes: Int = 15
    @AppStorage("autoScheduleAlertOnPark") private var autoScheduleOnPark: Bool = false

    private let ocrService = VisionOCRService()
    private let aiService = AIAnalyzerService()
    private let localParser = ParkingTextParser()
    
    @Query private var cars: [Car]
    @State private var selectedCarID: UUID? = nil

    // Auto-created or matched spot to edit after scan
    @State private var newSpotForEdit: ParkingSpot? = nil
    // Use this to attach analysis results to the correct spot if we merged/created by address
    @State private var analysisSpotOverride: ParkingSpot? = nil

    @State private var showSchedulePrompt: Bool = false
    @State private var promptCar: Car? = nil
    @State private var nextRestrictionForPrompt: Date? = nil
    @State private var pendingAlerts: [String: Date] = [:] // carID.uuidString -> next fire date

    private var currentUserID: UUID? {
        auth.currentUser?.id
    }
    
    private var spotCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
    }
    
    private var activeCarSession: ParkSession? {
        spot.parkSessions.first(where: { session in
            session.endedAt == nil && session.car != nil
        })
    }

    private var activeCar: Car? {
        activeCarSession?.car
    }
    
    private var lastScanSignalStatus: ParkingSignalStatus? {
        if let scan = spot.signScans.sorted(by: { $0.createdAt > $1.createdAt }).first {
            return ParkingSignalEvaluator.status(for: scan, now: Date(), leadMinutes: leadMinutes)
        }
        return nil
    }
    
    private var spotSignalStatus: ParkingSignalStatus { ParkingSignalEvaluator.status(for: spot, now: Date(), leadMinutes: leadMinutes) }

    private var carSelectionBinding: Binding<UUID?> {
        Binding<UUID?> (
            get: { selectedCarID },
            set: { newID in
                selectedCarID = newID
                assignSelectedCar()
            }
        )
    }

    var body: some View {
        List {
            signalStatusSection()
            parkingSection()
            upcomingSection()
            assignCarSection()
            locationSection()
            segmentMapPreviewSection()
            segmentEditorSection()
            cityDatasetSection()
            savedScanSection()
            restrictionsSection()
            dangerZoneSection()

            if isAnalyzing {
                analyzingSection()
            }

            if !ocrText.isEmpty {
                lastOCRSection()
            }

            if usedAIParsing != nil {
                parsingInfoSection()
            }

            if scanError != nil {
                scanErrorSection()
            }
        }
        .navigationTitle("Spot Details")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let userID = currentUserID ?? UUID()
                    newRestriction = Restriction(
                        type: .noParking,
                        startTime: Date(),
                        endTime: Date(),
                        daysOfWeek: [],
                        sourceUser: userID
                    )
                    showAddRestriction = true
                } label: {
                    Label("Add Restriction", systemImage: "plus")
                }
                .disabled(!auth.isAuthenticated)
                .help(auth.isAuthenticated ? "Add a restriction" : "Login to add restrictions")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    startScan()
                } label: {
                    Label("Quick Scan", systemImage: "camera.viewfinder")
                }
                .help("Take a photo of a street sign to analyze and set alarms")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showEditSpot.toggle()
                } label: {
                    Label("Edit Spot", systemImage: "pencil")
                }
                .help("Edit parking spot details")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    SpotPhotosView(spot: spot)
                } label: {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if let text = spot.lastScanText, !text.isEmpty {
                    Button {
                        Task { @MainActor in
                            // Force AI parsing for re-analysis regardless of the toggle
                            self.usedAIParsing = nil
                            self.aiFallbackReason = nil
                            self.ocrText = text
                            self.isAnalyzing = true
                            defer { self.isAnalyzing = false }
                            // Prefer AI, fallback to local inside runParsing
                            self.useAIParsing = true
                            await runParsing(for: text)
                        }
                    } label: {
                        Label("Re-Analyze (AI)", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .help("Re-run analysis with AI and update restrictions if desired")
                }
            }
        }
        .overlay(alignment: .top) {
            if showToast, let msg = toastMessage {
                Text(msg)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .sheet(isPresented: $showAddRestriction) {
            AddEditRestrictionView(
                restriction: $newRestriction,
                onSave: {
                    if let userID = currentUserID {
                        newRestriction.sourceUser = userID
                    }
                    if let existing = spot.restrictions.first(where: { $0.id == newRestriction.id }) {
                        // Update existing restriction in place
                        if let index = spot.restrictions.firstIndex(of: existing) {
                            spot.restrictions[index] = newRestriction
                        }
                    } else {
                        // Insert new restriction
                        context.insert(newRestriction)
                        newRestriction.spot = spot
                        spot.restrictions.append(newRestriction)
                    }
                    do {
                        try context.save()
                    } catch {
                        // In a real app, surface this to the user
                        print("Failed to save restriction: \(error)")
                    }
                    onUpdate?(spot)
                    Task { await enrichFromCityData() }
                },
                sourceUser: currentUserID ?? UUID()
            )
            .environmentObject(auth)
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                // Prepare quick review without auto-saving
                self.capturedImage = image
                self.pendingQuickImage = image
                self.showQuickReview = true
                // Compute OCR preview asynchronously (non-blocking)
                Task {
                    let preview = try? await ocrService.recognizeText(in: image)
                    await MainActor.run { self.pendingQuickOCRText = preview }
                }
            } onCancel: {
                isAnalyzing = false
            }
        }
        .sheet(isPresented: $showQuickReview) {
            if let img = pendingQuickImage {
                QuickScanReviewView(
                    image: img,
                    ocrPreview: pendingQuickOCRText,
                    onSubmit: { mergedText, filenames in
                        Task {
                            // Resolve coordinate and reverse geocode to an address label
                            let coord = currentDeviceCoordinate() ?? spotCoordinate
                            let address = await reverseGeocode(coord)
                            let label = (address ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? String(format: "%.5f, %.5f", coord.latitude, coord.longitude)
                                : address!

                            // Find or create a ParkingSpot by normalized address
                            let targetSpot: ParkingSpot = await MainActor.run {
                                let preferredSide = spot.streetSide
                                return SpotMergeService.findOrCreateSpot(address: address, coordinate: coord, in: context, preferredSide: preferredSide)
                            }

                            // Insert SignScan attached to the targetSpot
                            let scan = await MainActor.run { () -> SignScan in
                                let scan = SignScan(
                                    latitude: coord.latitude,
                                    longitude: coord.longitude,
                                    ocrText: mergedText,
                                    createdAt: Date(),
                                    photoFilename: filenames.first,
                                    additionalPhotoFilenames: Array(filenames.dropFirst()),
                                    photoFilenames: filenames,
                                    mergedOCRText: mergedText,
                                    address: address,
                                    status: "incomplete",
                                    sourceUser: currentUserID,
                                    spot: targetSpot,
                                    segmentCenterLat: coord.latitude,
                                    segmentCenterLon: coord.longitude,
                                    segmentRadius: 15.0,
                                    segmentStreetSide: targetSpot.streetSide
                                )
                                context.insert(scan)
                                targetSpot.attach(scan: scan)

                                // Assign to a curb segment (nearest on same side or create new)
                                let allScans = (try? context.fetch(FetchDescriptor<SignScan>())) ?? []
                                let loc = CLLocationCoordinate2D(latitude: scan.latitude, longitude: scan.longitude)
                                _ = SegmentManager.assign(
                                    scan: scan,
                                    existingScans: allScans.filter { $0.id != scan.id },
                                    currentLocation: loc,
                                    heading: scan.heading,
                                    preferredSide: StreetSide(rawValue: targetSpot.streetSide.lowercased()),
                                    defaultRadius: 15.0
                                )

                                try? context.save()
                                showToast(message: "Scan saved. Analyzing…")
                                return scan
                            }

                            // Track the correct spot for analysis result attachment and offer editing
                            await MainActor.run {
                                analysisSpotOverride = targetSpot
                                newSpotForEdit = targetSpot
                                self.ocrText = mergedText
                            }

                            // Run parsing pipeline (will present analysis sheet)
                            await runParsing(for: mergedText)

                            // Close review/camera UI
                            await MainActor.run {
                                self.showQuickReview = false
                                self.showCamera = false
                                self.pendingQuickImage = nil
                                self.pendingQuickOCRText = nil
                            }
                        }
                    },
                    onRetake: {
                        self.showQuickReview = false
                        self.showCamera = true
                        self.pendingQuickOCRText = nil
                    },
                    onDelete: {
                        self.showQuickReview = false
                        self.showCamera = false
                        self.pendingQuickImage = nil
                        self.pendingQuickOCRText = nil
                    }
                )
                .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $showAnalysisSheet) {
            if let analysis, let userID = currentUserID ?? Optional(UUID()) {
                VStack(spacing: 0) {
                    let status = ParkingSignalEvaluator.status(for: analysis, now: Date(), leadMinutes: leadMinutes)
                    HStack(spacing: 10) {
                        Image(systemName: status.iconName).foregroundStyle(status.color)
                        Text(status.label).font(.subheadline)
                        Spacer()
                    }
                    .padding(8)
                    .background(status.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding([.horizontal, .top])
                    AnalysisConfirmationView(
                        spot: analysisSpotOverride ?? spot,
                        sourceUser: userID,
                        ocrText: ocrText,
                        photoFilename: photoFilename,
                        analysis: analysis,
                        onFinished: { createdRestrictions in
                            onUpdate?(spot)
                            Task {
                                let activeSpot = analysisSpotOverride ?? spot
                                // Fetch alarms off the main actor
                                let alarms = await AlarmService.shared.allAlarms()
                                await MainActor.run {
                                    activeSpot.alarmIDs = alarms.map { $0.id }
                                    try? context.save()
                                }
                                // Upload only the newly confirmed restrictions
                                let lastScan: SignScan? = await MainActor.run {
                                    activeSpot.signScans.sorted(by: { $0.createdAt > $1.createdAt }).first
                                }
                                if let lastScan {
                                    try? await LocalStubBackendSyncService.shared.uploadRestrictions(for: lastScan, restrictions: createdRestrictions)
                                    await MainActor.run {
                                        // Link restrictions to this scan
                                        for r in createdRestrictions { r.scan = lastScan }
                                        lastScan.restrictions = createdRestrictions
                                        lastScan.status = "complete"
                                        let sig = ParkingSignalEvaluator.status(for: createdRestrictions, now: Date(), leadMinutes: leadMinutes)
                                        lastScan.signalState = sig.rawValue
                                        try? context.save()
                                        showToast(message: "Restrictions added successfully")
                                    }
                                }
                                analysisSpotOverride = nil
                            }
                        }
                    )
                    .environment(\.modelContext, context)
                }
            }
        }
        .sheet(item: $segmentEditScan) { scan in
            SegmentMapEditorView(scan: scan)
                .environment(\.modelContext, context)
        }
        .sheet(isPresented: $showEditSpot) {
            SpotEditView(spot: spot)
                .environment(\.modelContext, context)
        }
        .sheet(isPresented: $showCarPickerSheet) {
            NavigationStack {
                List {
                    Section("Select a Car") {
                        if cars.isEmpty {
                            Text("No cars found. Add a car in the Cars tab first.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(cars, id: \.id) { car in
                                Button {
                                    startParking(for: car)
                                    showCarPickerSheet = false
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: car.iconName).foregroundStyle(.tint)
                                        VStack(alignment: .leading) {
                                            Text(car.nickname)
                                            if let plate = car.licensePlate, !plate.isEmpty {
                                                Text(plate).font(.caption).foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Park Here")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showCarPickerSheet = false } }
                }
            }
        }
        .sheet(isPresented: $showMapSheet) {
            NavigationStack {
                Map(coordinateRegion: $mapRegion)
                    .ignoresSafeArea()
                    .navigationTitle(mapPinTitle ?? "Location")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showMapSheet = false }
                        }
                    }
            }
        }
        .sheet(item: $newSpotForEdit) { s in
            SpotEditView(spot: s)
                .environment(\.modelContext, context)
        }
        .onAppear {
            if let current = spot.parkSessions.first(where: { $0.endedAt == nil && $0.car != nil })?.car?.id {
                selectedCarID = current
            }
            refreshPendingAlerts()
        }
        .onChange(of: spot.parkSessions.map { $0.endedAt == nil ? ($0.car?.id ?? UUID()) : nil }.count) { _ in
            refreshPendingAlerts()
        }
        .alert("Schedule Alert?", isPresented: $showSchedulePrompt) {
            Button("Schedule") {
                if let car = promptCar { scheduleNextRestrictionNotification(for: car, at: spot); refreshPendingAlerts() }
                promptCar = nil
            }
            Button("Not now", role: .cancel) { promptCar = nil }
        } message: {
            if let when = nextRestrictionForPrompt {
                Text("Schedule an alert for \(when.formatted(date: .abbreviated, time: .shortened))?")
            } else {
                Text("Schedule an alert for the next restriction at this spot?")
            }
        }
        .alert("Delete Spot?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { deleteSpot() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove this spot, its scans, sessions, and restrictions. This action cannot be undone.")
        }
    }

    // MARK: - Section Builders
    @ViewBuilder
    private func signalStatusSection() -> some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: spotSignalStatus.iconName)
                    .foregroundStyle(spotSignalStatus.color)
                Text(spotSignalStatus.label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Circle()
                    .fill(spotSignalStatus.color.opacity(0.25))
                    .frame(width: 12, height: 12)
            }
        } header: {
            Text("Parking Signal")
        }
    }

    @ViewBuilder
    private func parkingSection() -> some View {
        Section(header: Text("Parking")) {
            if let car = activeCar {
                HStack(spacing: 8) {
                    Image(systemName: car.iconName)
                        .foregroundStyle(.tint)
                    Text("\(car.nickname) is parked here")
                        .foregroundStyle(.green)
                }
            }
            if spot.isCurrentlyParked {
                HStack(spacing: 8) {
                    Image(systemName: "parkingsign.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .green)
                    Text("You're parked here")
                        .foregroundStyle(.green)
                }
                Button(role: .destructive) {
                    endGenericParking()
                } label: {
                    Label("End Parking", systemImage: "xmark.circle")
                }
            } else {
                Text("Not parked here")
                    .foregroundColor(.secondary)
                Button {
                    showCarPickerSheet = true
                } label: {
                    Label("Park Here", systemImage: "parkingsign")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    @ViewBuilder
    private func upcomingSection() -> some View {
        Section(header: Text("Upcoming")) {
            // Upcoming restrictions for this spot (next 3)
            let items = upcomingRestrictions(limit: 3)
            if items.isEmpty {
                Text("No upcoming restrictions found.").foregroundColor(.secondary)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, entry in
                    let r = entry.0
                    let date = entry.1
                    HStack {
                        Image(systemName: "calendar")
                        VStack(alignment: .leading) {
                            Text(r.type.displayName)
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
            }

            // Scheduled alerts for currently parked cars at this spot
            let activeCarSessions = spot.parkSessions.filter { $0.endedAt == nil && $0.car != nil }
            if activeCarSessions.isEmpty {
                Text("No cars parked here.").foregroundColor(.secondary)
            } else {
                ForEach(activeCarSessions, id: \.id) { sess in
                    if let car = sess.car {
                        let key = car.id.uuidString
                        let fire = pendingAlerts[key]
                        HStack {
                            Image(systemName: car.iconName).foregroundStyle(.tint)
                            VStack(alignment: .leading) {
                                Text(car.nickname)
                                if let fire { Text("Alert: \(fire.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundColor(.secondary) }
                                else { Text("No alert scheduled").font(.caption).foregroundColor(.secondary) }
                            }
                            Spacer()
                            if fire == nil {
                                Button("Schedule") { scheduleNextRestrictionNotification(for: car, at: spot); refreshPendingAlerts() }
                                    .buttonStyle(.bordered)
                            } else {
                                Button("Cancel") { cancelAlert(for: car); refreshPendingAlerts() }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func assignCarSection() -> some View {
        Section("Assign Car to This Spot") {
            Picker("Car", selection: carSelectionBinding) {
                Text("None").tag(Optional<UUID>.none)
                ForEach(cars, id: \.id) { car in
                    Text(car.nickname).tag(Optional(car.id))
                }
            }
            if let selID = selectedCarID {
                if let active = activeSession(for: selID) {
                    Button(role: .destructive) {
                        endParking(for: selID)
                    } label: {
                        Label("End Parking for \(active.car?.nickname ?? "Car")", systemImage: "xmark.circle")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func locationSection() -> some View {
        Section(header: Text("Location")) {
            Button {
                let coord = spotCoordinate
                mapRegion = MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
                mapPinTitle = spot.location
                showMapSheet = true
            } label: {
                HStack {
                    Image(systemName: "mappin.and.ellipse")
                    Text(spot.location)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func segmentMapPreviewSection() -> some View {
        Section(header: Text("Map Preview")) {
            let last = spot.signScans.sorted(by: { $0.createdAt > $1.createdAt }).first
            let center = CLLocationCoordinate2D(
                latitude: last?.segmentCenterLat ?? last?.latitude ?? spot.latitude,
                longitude: last?.segmentCenterLon ?? last?.longitude ?? spot.longitude
            )
            Map(position: $mapPreviewPosition) {
                if let last, let dir = last.segmentDirection ?? last.heading {
                    let pts = CurbGeometry.curbAlignedPolyline(
                        center: center,
                        directionDegrees: dir,
                        sideRaw: last.segmentStreetSide ?? spot.streetSide,
                        lengthMeters: (last.segmentRadius ?? 15) * 2,
                        offsetMeters: 4.5
                    )
                    let status = ParkingSignalEvaluator.status(for: last, now: Date(), leadMinutes: leadMinutes)
                    MapPolyline(coordinates: pts)
                        .stroke(status.color.opacity(0.28), style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: pts)
                        .stroke(status.color, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                } else {
                    MapCircle(center: center, radius: 15)
                        .stroke(Color.accentColor.opacity(0.4), lineWidth: 2)
                        .foregroundStyle(Color.accentColor.opacity(0.08))
                }
                // Spot pin
                Annotation(spot.location, coordinate: CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                        .shadow(radius: 1)
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    Button {
                        let coord = spotCoordinate
                        mapRegion = MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
                        mapPinTitle = spot.location
                        showMapSheet = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Button {
                        if let scan = lastScan {
                            segmentEditScan = scan
                        } else {
                            let scan = createOrFetchSegmentScan()
                            segmentEditScan = scan
                        }
                    } label: {
                        Image(systemName: "pencil.and.outline")
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(8)
            }
            .onAppear {
                mapPreviewPosition = .region(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.0025, longitudeDelta: 0.0025)))
            }
        }
    }

    @ViewBuilder
    private func segmentEditorSection() -> some View {
        Section(header: Text("Curb Segment")) {
            if let scan = lastScan {
                VStack(alignment: .leading, spacing: 6) {
                    if let lat = scan.segmentCenterLat, let lon = scan.segmentCenterLon {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin")
                            Text(String(format: "Center: %.5f, %.5f", lat, lon))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin")
                            Text("Center: not set")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.and.right")
                        Text("Side: \((scan.segmentStreetSide ?? spot.streetSide).capitalized)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "ruler")
                        Text("Length: ~\(Int((scan.segmentRadius ?? 15) * 2)) m")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Slider(value: Binding<Double>(
                        get: { (scan.segmentRadius ?? 15) * 2 },
                        set: { newLength in
                            scan.segmentRadius = max(5, newLength / 2)
                            try? context.save()
                        }
                    ), in: 10...100, step: 2)

                    Toggle("Specify Direction", isOn: Binding<Bool>(
                        get: { (scan.segmentDirection ?? scan.heading) != nil },
                        set: { on in
                            if on {
                                // If no explicit direction yet, use existing heading or 0
                                if scan.segmentDirection == nil { scan.segmentDirection = scan.heading ?? 0 }
                            } else {
                                scan.segmentDirection = nil
                            }
                            try? context.save()
                        }
                    ))

                    if (scan.segmentDirection ?? scan.heading) != nil {
                        let dir = (scan.segmentDirection ?? scan.heading ?? 0)
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond")
                            Text("Direction: \(Int(dir))°")
                            Spacer()
                        }
                        Slider(value: Binding<Double>(
                            get: { scan.segmentDirection ?? dir },
                            set: { nv in
                                scan.segmentDirection = CurbGeometry.normalizedHeading(nv)
                                try? context.save()
                            }
                        ), in: 0...360, step: 1)
                    }

                    HStack {
                        Button {
                            // Use scan raw pin as center
                            scan.segmentCenterLat = scan.latitude
                            scan.segmentCenterLon = scan.longitude
                            try? context.save()
                        } label: {
                            Label("Use Scan as Center", systemImage: "mappin")
                        }

                        Spacer()

                        Button {
                            // Use device location as center if available
                            if let c = currentDeviceCoordinate() {
                                scan.segmentCenterLat = c.latitude
                                scan.segmentCenterLon = c.longitude
                                try? context.save()
                            }
                        } label: {
                            Label("Use My Location", systemImage: "location")
                        }
                    }

                    HStack {
                        Button {
                            segmentEditScan = scan
                        } label: {
                            Label("Edit on Map", systemImage: "pencil.and.outline")
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button(role: .destructive) {
                            clearSegment(for: scan)
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        scan.segmentCenterLat = spot.latitude
                        scan.segmentCenterLon = spot.longitude
                        try? context.save()
                    } label: {
                        Label("Use Spot as Center", systemImage: "mappin.circle")
                    }
                }
            } else {
                Text("No scans yet for this spot.")
                    .foregroundColor(.secondary)
                Button {
                    let scan = createOrFetchSegmentScan()
                    segmentEditScan = scan
                } label: {
                    Label("Create Segment", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func cityDatasetSection() -> some View {
        Section(header: Text("City Dataset (Sample)")) {
            if let name = matchedCityName {
                Text("Matched city: \(name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No sample dataset for this area")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button {
                Task { await fetchCityRestrictions() }
            } label: {
                Label(loadingCityData ? "Fetching…" : (cityRestrictions.isEmpty ? "Fetch Nearby Restrictions" : "Refresh Nearby Restrictions"), systemImage: "arrow.clockwise")
            }
            .disabled(loadingCityData)

            if loadingCityData {
                HStack { ProgressView(); Text("Loading nearby restrictions…") }
            }

            if let err = cityDataError {
                Text(err).foregroundColor(.red)
            }

            if !cityRestrictions.isEmpty {
                ForEach(Array(cityRestrictions.enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.type.displayName).font(.headline)
                        Text("\(daysDescription(r.daysOfWeek)) • \(r.startTime) - \(r.endTime)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if let n = r.notes, !n.isEmpty { Text(n).font(.caption).foregroundColor(.secondary) }
                    }
                }
                Button {
                    Task { await importCityRestrictions() }
                } label: {
                    Label("Import into This Spot", systemImage: "tray.and.arrow.down")
                }
            }
        }
    }

    @ViewBuilder
    private func savedScanSection() -> some View {
        Section(header: HStack { 
            Text("Saved Scan")
            Spacer()
            if let s = lastScanSignalStatus {
                Circle().fill(s.color).frame(width: 10, height: 10)
            }
        }) {
            if let last = spot.signScans.sorted(by: { $0.createdAt > $1.createdAt }).first {
                Button {
                    let coord = CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)
                    mapRegion = MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
                    mapPinTitle = resolvedSavedScanAddress ?? last.address ?? String(format: "%.5f, %.5f", last.latitude, last.longitude)
                    showMapSheet = true
                } label: {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                        Text(resolvedSavedScanAddress ?? last.address ?? String(format: "%.5f, %.5f", last.latitude, last.longitude))
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary)
                    }
                }
                .task {
                    if (last.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let addr = await reverseGeocode(CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude))
                        await MainActor.run {
                            self.resolvedSavedScanAddress = addr
                            if let a = addr, !a.isEmpty {
                                last.address = a
                                try? context.save()
                            }
                        }
                    } else {
                        resolvedSavedScanAddress = last.address
                    }
                }

                if let segLat = last.segmentCenterLat, let segLon = last.segmentCenterLon {
                    HStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2")
                        Text("Segment: \(last.segmentStreetSide?.capitalized ?? "?") • radius ~\(Int(last.segmentRadius ?? 15))m")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }

            if let text = spot.lastScanText, !text.isEmpty {
                Text(text)
                    .textSelection(.enabled)
            } else {
                Text("No scan saved.")
                    .foregroundColor(.secondary)
            }
            if let filename = spot.lastScanPhotoFilename {
                if let img = ImageStore.loadImage(named: filename) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.15))
                        Image(systemName: "photo")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.secondary)
                            .padding(24)
                    }
                    .frame(maxHeight: 180)
                }
            }
            if let t = spot.lastScanAt {
                Text("Scanned: \(t.formatted())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func restrictionsSection() -> some View {
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
                .swipeActions {
                    Button("Edit") {
                        newRestriction = restriction
                        showAddRestriction = true
                    }
                    .tint(.blue)
                }
            }
            .onDelete { indexSet in
                let items = indexSet.map { spot.restrictions[$0] }
                for r in items {
                    context.delete(r)
                }
                spot.restrictions.remove(atOffsets: indexSet)
                try? context.save()
            }
            if spot.restrictions.isEmpty {
                Text("No restrictions recorded.")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func dangerZoneSection() -> some View {
        Section {
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label("Delete Spot", systemImage: "trash")
            }
        } header: {
            Text("Danger Zone")
        }
    }

    @ViewBuilder
    private func analyzingSection() -> some View {
        Section {
            HStack {
                ProgressView()
                Text("Analyzing sign…")
            }
        }
    }

    @ViewBuilder
    private func lastOCRSection() -> some View {
        Section(header: Text("Last OCR Text")) {
            Text(ocrText)
                .textSelection(.enabled)
                .font(.body.monospaced())
        }
    }

    @ViewBuilder
    private func parsingInfoSection() -> some View {
        Section {
            HStack {
                Image(systemName: (usedAIParsing ?? false) ? "bolt.horizontal.circle" : "cpu")
                Text((usedAIParsing ?? false) ? "Parsed using AI" : "Parsed locally")
                    .font(.subheadline)
                Spacer()
                if let reason = aiFallbackReason, usedAIParsing == false {
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func scanErrorSection() -> some View {
        if let scanError {
            Section {
                Text(scanError)
                    .foregroundColor(.red)
            }
        }
    }

    private func assignSelectedCar() {
        guard let selID = selectedCarID, let car = cars.first(where: { $0.id == selID }) else { return }
        do {
            // End any active session for this car
            let all = try context.fetch(FetchDescriptor<ParkSession>())
            for s in all where s.car?.id == car.id && s.endedAt == nil { s.endedAt = Date() }
            // Start a new session at this spot
            let session = ParkSession(spot: spot, startedAt: Date(), endedAt: nil, car: car)
            context.insert(session)
            try context.save()
            if autoScheduleOnPark {
                scheduleNextRestrictionNotification(for: car, at: spot)
            } else {
                promptCar = car
                nextRestrictionForPrompt = spot.nextRestrictionDate()
                showSchedulePrompt = true
            }
        } catch { }
    }

    private func endParking(for carID: UUID) {
        do {
            let all = try context.fetch(FetchDescriptor<ParkSession>())
            for s in all where s.car?.id == carID && s.spot?.id == spot.id && s.endedAt == nil { s.endedAt = Date() }
            try context.save()
        } catch { }
    }

    private func scheduleNextRestrictionNotification(for car: Car, at spot: ParkingSpot) {
        guard let next = spot.nextRestrictionDate() else { return }
        let center = UNUserNotificationCenter.current()
        let id = "nextRestriction.car.\(car.id.uuidString).spot.\(spot.id.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let content = UNMutableNotificationContent()
        content.title = "Move your \(car.nickname)"
        content.body = "Restriction at \(spot.location) starts soon."
        content.sound = .default
        if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: next)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(req)
        // Save routing metadata as well for AlarmService to match
        Task { @MainActor in
            AlarmService.shared.objectWillChange.send()
            // store metadata for notification
            // We can't call a private save method here; instead schedule an AlarmKit countdown with metadata
            let seconds = next.timeIntervalSinceNow
            if seconds > 1 {
                _ = await AlarmService.shared.requestAuthorization()
                do {
                    let _ = try await AlarmService.shared.scheduleCountdown(seconds: seconds, title: LocalizedStringResource("Restriction Starts"), carID: car.id, spotID: spot.id)
                } catch { }
            }
        }
    }

    private func cancelAlert(for car: Car) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map { $0.identifier }.filter { $0.hasPrefix("nextRestriction.car.\(car.id.uuidString).spot.") }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private func refreshPendingAlerts() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { reqs in
            var map: [String: Date] = [:]
            let active = spot.parkSessions.filter { $0.endedAt == nil && $0.car != nil }
            for s in active {
                if let car = s.car {
                    let idPrefix = "nextRestriction.car.\(car.id.uuidString).spot."
                    if let r = reqs.first(where: { $0.identifier.hasPrefix(idPrefix) }), let trig = r.trigger as? UNCalendarNotificationTrigger, let date = trig.nextTriggerDate() {
                        map[car.id.uuidString] = date
                    }
                }
            }
            DispatchQueue.main.async { self.pendingAlerts = map }
        }
    }

    private func upcomingRestrictions(limit: Int = 3, from now: Date = Date()) -> [(Restriction, Date)] {
        let cal = Calendar.current
        var results: [(Restriction, Date)] = []
        for r in spot.restrictions {
            // Skip if days not set; we can't predict windows
            let days = r.daysOfWeek
            if days.isEmpty { continue }
            // For the next 14 days, collect starts
            for offset in 0...13 {
                guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
                let w = (cal.component(.weekday, from: day) + 6) % 7
                guard days.contains(w) else { continue }
                let sh = cal.component(.hour, from: r.startTime)
                let sm = cal.component(.minute, from: r.startTime)
                var comps = cal.dateComponents([.year, .month, .day], from: day)
                comps.hour = sh; comps.minute = sm; comps.second = 0
                if let start = cal.date(from: comps), start > now {
                    results.append((r, start))
                }
            }
        }
        results.sort { $0.1 < $1.1 }
        if results.count > limit { return Array(results.prefix(limit)) }
        return results
    }

    private func activeSession(for carID: UUID) -> ParkSession? {
        spot.parkSessions.first(where: { session in
            session.endedAt == nil && session.car?.id == carID
        })
    }

    private func startScan() {
        scanError = nil
        isAnalyzing = false
        capturedImage = nil
        ocrText = ""
        analysis = nil
        photoFilename = nil
        showCamera = true
    }

    @MainActor
    private func processCapturedImage() async {
        guard let image = capturedImage else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            // Save image first to link to restrictions later
            photoFilename = try ImageStore.saveJPEG(image)

            // OCR (on-device)
            let text = try await ocrService.recognizeText(in: image)
            ocrText = text

            spot.lastScanText = text
            spot.lastScanPhotoFilename = photoFilename
            spot.lastScanAt = Date()
            try? context.save()

            try await runParsing(for: text)
        } catch {
            scanError = error.localizedDescription
        }
    }

    @MainActor
    private func processRecognizedText(_ text: String) async {
        ocrText = text

        spot.lastScanText = text
        spot.lastScanAt = Date()
        try? context.save()

        await runParsing(for: text)
    }

    @MainActor
    private func runParsing(for text: String) async {
        isAnalyzing = true
        defer { isAnalyzing = false }
        usedAIParsing = nil
        aiFallbackReason = nil
        do {
            if useAIParsing {
                do {
                    let result = try await aiService.analyzeWithDebug(ocrText: text)
                    analysis = result.parsed
                    usedAIParsing = true
                } catch {
                    // Record fallback reason and use local parsing
                    aiFallbackReason = error.localizedDescription
                    analysis = localParser.analyze(ocrText: text)
                    usedAIParsing = false
                }
            } else {
                analysis = localParser.analyze(ocrText: text)
                usedAIParsing = false
            }
            if let analysis, !analysis.restrictions.isEmpty {
                showAnalysisSheet = true
            }
        } catch {
            scanError = error.localizedDescription
        }
    }

    private func startGenericParking() {
        do {
            // End any open generic ParkSession (no car) across all spots
            let all = try context.fetch(FetchDescriptor<ParkSession>())
            for s in all where s.endedAt == nil && s.car == nil { s.endedAt = Date() }

            // Start a new session at this spot
            let session = ParkSession(spot: spot, startedAt: Date(), endedAt: nil, car: nil)
            context.insert(session)
            try context.save()

            // Schedule notifications for this spot's restrictions
            Task { await NotificationManager.shared.schedule(for: spot.restrictions, spot: spot) }
        } catch {
            print("Failed to start parking: \(error)")
        }
    }

    private func endGenericParking() {
        do {
            let all = try context.fetch(FetchDescriptor<ParkSession>())
            for s in all where s.endedAt == nil && s.spot?.id == spot.id && s.car == nil { s.endedAt = Date() }
            try context.save()
        } catch {
            print("Failed to end parking: \(error)")
        }
    }
    
    private func enrichFromCityData() async {
        await ParkingDataProvider.shared.bootstrapIfNeeded(currentLocation: spotCoordinate)
        let cityRestrictions = await ParkingDataProvider.shared.restrictionsNear(spotCoordinate)
        guard !cityRestrictions.isEmpty else { return }
        for cr in cityRestrictions {
            let start = DateTimeUtils.parseHHmm(cr.startTime) ?? (8, 0)
            let end = DateTimeUtils.parseHHmm(cr.endTime) ?? (10, 0)
            let startDate = DateTimeUtils.todayAt(hour: start.0, minute: start.1)
            var endDate = DateTimeUtils.todayAt(hour: end.0, minute: end.1)
            if endDate <= startDate { endDate = endDate.addingTimeInterval(24*60*60) }
            let r = Restriction(type: cr.type, startTime: startDate, endTime: endDate, daysOfWeek: cr.daysOfWeek, sourceUser: UUID(), signPhotoFilename: nil, ocrText: "City dataset", spot: spot)
            context.insert(r)
            spot.restrictions.append(r)
        }
        try? context.save()
        await NotificationManager.shared.schedule(for: spot.restrictions, spot: spot)
    }

    @MainActor
    private func fetchCityRestrictions() async {
        loadingCityData = true
        cityDataError = nil
        cityRestrictions = []
        await ParkingDataProvider.shared.bootstrapIfNeeded(currentLocation: spotCoordinate)
        matchedCityName = ParkingDataProvider.shared.matchedCity?.cityName
        let items = await ParkingDataProvider.shared.restrictionsNear(spotCoordinate)
        if items.isEmpty {
            if matchedCityName == nil {
                cityDataError = "No sample dataset available for this area. Try a spot in San Francisco or New York City."
            } else {
                cityDataError = "No sample restrictions found near this spot. Try moving closer to the city center."
            }
            let gen = UINotificationFeedbackGenerator(); gen.notificationOccurred(.warning)
        } else {
            cityRestrictions = items
            let gen = UINotificationFeedbackGenerator(); gen.notificationOccurred(.success)
        }
        loadingCityData = false
    }

    @MainActor
    private func importCityRestrictions() async {
        guard !cityRestrictions.isEmpty else { return }
        for cr in cityRestrictions {
            let start = DateTimeUtils.parseHHmm(cr.startTime) ?? (8, 0)
            let end = DateTimeUtils.parseHHmm(cr.endTime) ?? (10, 0)
            let startDate = DateTimeUtils.todayAt(hour: start.0, minute: start.1)
            var endDate = DateTimeUtils.todayAt(hour: end.0, minute: end.1)
            if endDate <= startDate { endDate = endDate.addingTimeInterval(24 * 60 * 60) }
            let r = Restriction(type: cr.type, startTime: startDate, endTime: endDate, daysOfWeek: cr.daysOfWeek, sourceUser: UUID(), signPhotoFilename: nil, ocrText: "City dataset", spot: spot)
            context.insert(r)
            spot.restrictions.append(r)
        }
        try? context.save()
        await NotificationManager.shared.schedule(for: spot.restrictions, spot: spot)
    }

    private func daysDescription(_ days: [Int]) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols // Sun..Sat
        let labels = days.compactMap { (0...6).contains($0) ? symbols[$0] : nil }
        return labels.isEmpty ? "None" : labels.joined(separator: ", ")
    }

    private func startParking(for car: Car) {
        do {
            // End any active session for this car
            let all = try context.fetch(FetchDescriptor<ParkSession>())
            for s in all where s.car?.id == car.id && s.endedAt == nil { s.endedAt = Date() }
            // Start a new session at this spot
            let session = ParkSession(spot: spot, startedAt: Date(), endedAt: nil, car: car)
            context.insert(session)
            try context.save()
            if autoScheduleOnPark {
                scheduleNextRestrictionNotification(for: car, at: spot)
            } else {
                promptCar = car
                nextRestrictionForPrompt = spot.nextRestrictionDate()
                showSchedulePrompt = true
            }
        } catch { }
    }

    private func currentDeviceCoordinate() -> CLLocationCoordinate2D? {
        let manager = CLLocationManager()
        return manager.location?.coordinate
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> String? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if let p = placemarks.first {
                let parts = [p.name, p.locality, p.administrativeArea].compactMap { $0 }.filter { !$0.isEmpty }
                if !parts.isEmpty { return parts.joined(separator: ", ") }
                if let line = p.postalAddress?.street { return line }
            }
            return nil
        } catch {
            return nil
        }
    }

    private func normalized(_ s: String?) -> String {
        return (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    @MainActor
    private func showToast(message: String) {
        self.toastMessage = message
        withAnimation { self.showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { self.showToast = false }
            self.toastMessage = nil
        }
    }
    
    private func deleteSpot() {
        // Cancel pending alerts for any cars parked here
        let active = spot.parkSessions.filter { $0.endedAt == nil && $0.car != nil }
        for s in active { if let car = s.car { cancelAlert(for: car) } }

        // Delete child objects explicitly to avoid dangling references
        for r in spot.restrictions { context.delete(r) }
        for s in spot.signScans { context.delete(s) }
        for ps in spot.parkSessions { context.delete(ps) }

        // Finally delete the spot
        context.delete(spot)
        do { try context.save() } catch { }
        dismiss()
    }

    @MainActor
    private func createOrFetchSegmentScan() -> SignScan {
        if let scan = lastScan { return scan }
        let coord = spotCoordinate
        let scan = SignScan(
            latitude: coord.latitude,
            longitude: coord.longitude,
            ocrText: "",
            createdAt: Date(),
            photoFilename: nil,
            additionalPhotoFilenames: [],
            photoFilenames: [],
            mergedOCRText: "",
            address: spot.location,
            status: "incomplete",
            sourceUser: currentUserID,
            spot: spot,
            segmentCenterLat: coord.latitude,
            segmentCenterLon: coord.longitude,
            segmentRadius: 15.0,
            segmentStreetSide: spot.streetSide
        )
        context.insert(scan)
        spot.attach(scan: scan)
        try? context.save()
        return scan
    }

    private func clearSegment(for scan: SignScan) {
        scan.segmentCenterLat = nil
        scan.segmentCenterLon = nil
        scan.segmentRadius = nil
        scan.segmentDirection = nil
        try? context.save()
    }

    @ViewBuilder
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
}
