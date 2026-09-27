import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import CoreLocation
import Contacts
import MapKit
import Combine

struct ParkingSpotDetailView: View {
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
        sourceUser: LocalIdentity.userID
    )
    @State private var showEditSpot = false

    // Scan flow state
    @State private var showCamera = false
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
    @State private var showDeleteAlert: Bool = false

    // Segment editing state
    @State private var segmentEditScan: SignScan? = nil

    private var lastScan: SignScan? {
        spot.signScans.sorted(by: { $0.createdAt > $1.createdAt }).first
    }

    @AppStorage("alertLeadMinutes") private var leadMinutes: Int = 15

    private let ocrService = VisionOCRService()
    private let localParser = ParkingTextParser()
    
    @Query private var cars: [Car]
    @StateObject private var locationManager = LocationManager()
    @State private var parking = SpotParkingModel()

    // Auto-created or matched spot to edit after scan
    @State private var newSpotForEdit: ParkingSpot? = nil
    // Use this to attach analysis results to the correct spot if we merged/created by address
    @State private var analysisSpotOverride: ParkingSpot? = nil


    private var currentUserID: UUID? {
        LocalIdentity.userID
    }
    
    private var spotCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
    }
    
    private var lastScanSignalStatus: ParkingSignalStatus? {
        if let scan = spot.signScans.sorted(by: { $0.createdAt > $1.createdAt }).first {
            return ParkingSignalEvaluator.status(for: scan, now: Date(), leadMinutes: leadMinutes)
        }
        return nil
    }
    
    private var spotSignalStatus: ParkingSignalStatus { ParkingSignalEvaluator.status(for: spot, now: Date(), leadMinutes: leadMinutes) }

    var body: some View {
        List {
            signalStatusSection()
            SpotParkingSections(spot: spot, model: parking)
            locationSection()
            SpotSegmentSections(
                spot: spot,
                segmentEditScan: $segmentEditScan,
                deviceCoordinate: locationManager.lastLocation?.coordinate,
                presentMap: presentMap
            )
            SpotCityDataSection(spot: spot)
            savedScanSection()
            restrictionsSection()
            SpotDangerZoneSection { showDeleteAlert = true }

            SpotScanStatusSections(
                isAnalyzing: isAnalyzing,
                ocrText: ocrText,
                usedAIParsing: usedAIParsing,
                aiFallbackReason: aiFallbackReason,
                scanError: scanError
            )
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
                            self.usedAIParsing = nil
                            self.aiFallbackReason = nil
                            self.ocrText = text
                            self.isAnalyzing = true
                            defer { self.isAnalyzing = false }
                            await runParsing(for: text)
                        }
                    } label: {
                        Label("Re-Analyze", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .help("Re-run analysis on this scan's text and update restrictions")
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
                    }
                    onUpdate?(spot)
                    // Cancel any prior alarms for this restriction id (handles edits that
                    // change days/times), then (re)schedule from the saved values.
                    let saved = newRestriction
                    Task {
                        await NotificationManager.shared.cancel(forRestrictionIDs: [saved.id])
                        await NotificationManager.shared.schedule(for: [saved], spot: spot)
                    }
                    Task { await enrichFromCityData() }
                },
                sourceUser: currentUserID ?? UUID()
            )
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                // Prepare quick review without auto-saving
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
                        Task { @MainActor in
                            // Resolve coordinate and reverse geocode to an address label
                            let coord = locationManager.lastLocation?.coordinate ?? spotCoordinate
                            let address = await reverseGeocode(coord)

                            // Find or create a ParkingSpot by normalized address (main actor)
                            let preferredSide = spot.streetSide
                            let targetSpot = SpotMergeService.findOrCreateSpot(address: address, coordinate: coord, in: context, preferredSide: preferredSide)

                            // Insert SignScan attached to the targetSpot
                            await MainActor.run {
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
                            .accessibilityHidden(true)
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
                            Task { @MainActor in
                                let activeSpot = analysisSpotOverride ?? spot
                                // Fetch alarms (async) then record their ids
                                let alarms = await AlarmService.shared.allAlarms()
                                activeSpot.alarmIDs = alarms.map { $0.id }
                                try? context.save()
                                // Upload only the newly confirmed restrictions
                                let lastScan: SignScan? = activeSpot.signScans.sorted(by: { $0.createdAt > $1.createdAt }).first
                                if let lastScan {
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
        .sheet(isPresented: $parking.showCarPicker) {
            NavigationStack {
                List {
                    Section("Select a Car") {
                        if cars.isEmpty {
                            Text("No cars found. Add a car in the Cars tab first.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(cars, id: \.id) { car in
                                Button {
                                    parking.park(car, at: spot, context: context)
                                    parking.showCarPicker = false
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
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { parking.showCarPicker = false } }
                }
            }
        }
        .sheet(isPresented: $showMapSheet) {
            NavigationStack {
                Map(initialPosition: .region(mapRegion))
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
                parking.selectedCarID = current
            }
            parking.refresh(for: spot)
            locationManager.ensureAuthorized()
        }
        .onDisappear {
            locationManager.stopUpdatingLocation()
        }
        .onChange(of: spot.parkSessions.map { $0.endedAt == nil ? ($0.car?.id ?? UUID()) : nil }.count) { _, _ in
            parking.refresh(for: spot)
        }
        .alert("Schedule Alert?", isPresented: $parking.showSchedulePrompt) {
            Button("Schedule") {
                if let car = parking.promptCar { parking.scheduleMoveAlert(for: car, at: spot, context: context) }
                parking.promptCar = nil
            }
            Button("Not now", role: .cancel) { parking.promptCar = nil }
        } message: {
            if let when = parking.nextRestrictionForPrompt {
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
                    .accessibilityHidden(true)
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
                            .minimumScaleFactor(0.75)
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

                if last.segmentCenterLat != nil, last.segmentCenterLon != nil {
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
                let ids = items.map { $0.id }
                for r in items {
                    context.delete(r)
                }
                spot.restrictions.remove(atOffsets: indexSet)
                try? context.save()
                // Remove the deleted restrictions' repeating alarms.
                Task { await NotificationManager.shared.cancel(forRestrictionIDs: ids) }
            }
            if spot.restrictions.isEmpty {
                Text("No restrictions recorded.")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var sessions: ParkingSessionService { ParkingSessionService(context: context) }

    private func startScan() {
        scanError = nil
        isAnalyzing = false
        ocrText = ""
        analysis = nil
        photoFilename = nil
        showCamera = true
    }

    @MainActor
    private func runParsing(for text: String) async {
        isAnalyzing = true
        defer { isAnalyzing = false }
        // v1 interprets signs on-device (no cloud AI).
        usedAIParsing = false
        aiFallbackReason = nil
        analysis = localParser.analyze(ocrText: text)
        if let analysis, !analysis.restrictions.isEmpty {
            showAnalysisSheet = true
        }
    }

    private func enrichFromCityData() async {
        await CityRestrictionImporter.importNear(spot: spot, context: context)
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> String? {
        await SpotLocationUtils.reverseGeocode(coordinate)
    }

    private func presentMap(_ coordinate: CLLocationCoordinate2D, _ title: String?) {
        mapRegion = MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
        mapPinTitle = title
        showMapSheet = true
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
        let parkedCarIDs = active.compactMap { $0.car?.id }
        let service = sessions
        Task { for id in parkedCarIDs { await service.cancelMoveAlert(forCarID: id) } }

        // Cancel the repeating weekly alarms for this spot's restrictions before deleting.
        let restrictionIDs = spot.restrictions.map { $0.id }
        Task { await NotificationManager.shared.cancel(forRestrictionIDs: restrictionIDs) }

        // Delete child objects explicitly to avoid dangling references
        for r in spot.restrictions { context.delete(r) }
        for s in spot.signScans { context.delete(s) }
        for ps in spot.parkSessions { context.delete(ps) }

        // Finally delete the spot
        context.delete(spot)
        do { try context.save() } catch { }
        dismiss()
    }

}
