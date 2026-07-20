import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import Contacts
#if canImport(UIKit)
import UIKit
#endif

struct SignScanEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var scan: SignScan

    @State private var resolvedAddress: String? = nil

    @AppStorage("alertLeadMinutes") private var leadMinutes: Int = 15

    // Parsing services
    private let aiService = AIAnalyzerService()
    private let localParser = ParkingTextParser()

    @State private var isAnalyzingScan: Bool = false
    @State private var analyzeError: String? = nil
    @State private var analyzeInfo: String? = nil
    
    // Editable segment state
    @State private var segSide: StreetSide = .right
    @State private var segRadius: Double = 15
    @State private var segHasDirection: Bool = false
    @State private var segDirection: Double = 0

    @State private var showSegmentMapEditor = false

    var body: some View {
        Form {
            Section("OCR Text") {
                TextEditor(text: $scan.ocrText)
                    .frame(minHeight: 120)
            }
            Section("Location") {
                Button {
                    let coord = CLLocationCoordinate2D(latitude: scan.latitude, longitude: scan.longitude)
                    let destination = MKMapItem(placemark: MKPlacemark(coordinate: coord))
                    destination.name = resolvedAddress ?? scan.address ?? String(format: "%.5f, %.5f", scan.latitude, scan.longitude)
                    MKMapItem.openMaps(
                        with: [MKMapItem.forCurrentLocation(), destination],
                        launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
                    )
                } label: {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                        Text(resolvedAddress ?? scan.address ?? String(format: "%.5f, %.5f", scan.latitude, scan.longitude))
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary)
                    }
                }
            }
            Section("Segment") {
                // Side picker
                Picker("Side", selection: $segSide) {
                    Text("Left").tag(StreetSide.left)
                    Text("Right").tag(StreetSide.right)
                }
                .pickerStyle(.segmented)
                .onChange(of: segSide) { newValue in
                    scan.segmentStreetSide = newValue.rawValue
                }

                // Radius slider
                HStack(spacing: 8) {
                    Image(systemName: "ruler")
                    Text("Radius: ~\(Int(segRadius)) m")
                    Spacer()
                }
                Slider(value: $segRadius, in: 5...50, step: 1)
                    .onChange(of: segRadius) { newValue in
                        scan.segmentRadius = newValue
                    }

                // Direction controls
                Toggle("Specify Direction", isOn: $segHasDirection)
                    .onChange(of: segHasDirection) { on in
                        if on {
                            scan.segmentDirection = CurbGeometry.normalizedHeading(segDirection)
                        } else {
                            scan.segmentDirection = nil
                        }
                    }

                if segHasDirection {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        Text("Direction: \(Int(segDirection))°")
                        Spacer()
                    }
                    Slider(value: $segDirection, in: 0...360, step: 1)
                        .onChange(of: segDirection) { newValue in
                            scan.segmentDirection = CurbGeometry.normalizedHeading(newValue)
                        }
                } else {
                    if let heading = scan.heading {
                        Button {
                            segDirection = CurbGeometry.normalizedHeading(heading)
                            segHasDirection = true
                            scan.segmentDirection = segDirection
                        } label: {
                            Label("Use Device Heading (\(Int(heading))°)", systemImage: "location.north.line")
                        }
                    }
                }

                // Center display and actions
                if let lat = scan.segmentCenterLat, let lon = scan.segmentCenterLon {
                    HStack {
                        Image(systemName: "mappin")
                        Text(String(format: "Center: %.5f, %.5f", lat, lon))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    HStack {
                        Image(systemName: "mappin")
                        Text("Center: not set")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }

                Button {
                    scan.segmentCenterLat = scan.latitude
                    scan.segmentCenterLon = scan.longitude
                } label: {
                    Label("Use Scan Location as Center", systemImage: "mappin.circle")
                }
                
                Button {
                    // Open the same map editor but allow moving the raw pin as well by setting segment center to raw pin after edit
                    showSegmentMapEditor = true
                } label: {
                    Label("Edit Sign Pin on Map", systemImage: "mappin")
                }

                if let spot = scan.spot {
                    Button {
                        let a = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
                        let b = CLLocationCoordinate2D(latitude: scan.latitude, longitude: scan.longitude)
                        let dir = SegmentUtils.bearingDegrees(from: a, to: b)
                        segDirection = CurbGeometry.normalizedHeading(dir)
                        segHasDirection = true
                        scan.segmentDirection = segDirection
                    } label: {
                        Label("Infer Direction from Spot", systemImage: "arrow.triangle.turn.up.right.circle")
                    }
                }

                Button {
                    showSegmentMapEditor = true
                } label: {
                    Label("Edit on Map", systemImage: "map")
                }
            }
            Section("Photo") {
                if let uiImage = loadScanUIImage() {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("No photo available")
                        .foregroundColor(.secondary)
                }
            }
            Section("Analysis") {
                if isAnalyzingScan {
                    HStack { ProgressView(); Text("Analyzing…") }
                } else {
                    Button {
                        Task { await analyzeSavedScan() }
                    } label: {
                        Label("Analyze Scan", systemImage: "bolt.horizontal.circle")
                    }
                }
                if let info = analyzeInfo {
                    Text(info).font(.footnote).foregroundColor(.secondary)
                }
                if let err = analyzeError {
                    Text(err).foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Edit Scan")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    // The scan is a SwiftData @Model instance; just save changes.
                    try? modelContext.save()
                    dismiss()
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            // Initialize segment editing state from current scan values
            let sideRaw = (scan.segmentStreetSide ?? scan.spot?.streetSide ?? "right").lowercased()
            segSide = StreetSide(rawValue: sideRaw) ?? .right
            segRadius = scan.segmentRadius ?? 15
            if let dir = scan.segmentDirection ?? scan.heading {
                segHasDirection = true
                segDirection = CurbGeometry.normalizedHeading(dir)
            } else {
                segHasDirection = false
                segDirection = 0
            }
        }
        .task {
            let coord = CLLocationCoordinate2D(latitude: scan.latitude, longitude: scan.longitude)
            if (scan.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let addr = await reverseGeocode(coord) {
                    resolvedAddress = addr
                    scan.address = addr
                    try? modelContext.save()
                } else {
                    resolvedAddress = nil
                }
            } else {
                resolvedAddress = scan.address
            }
        }
        .sheet(isPresented: $showSegmentMapEditor) {
            SegmentMapEditorView(scan: scan)
                .environment(\.modelContext, modelContext)
        }
    }

    @MainActor
    private func analyzeSavedScan() async {
        analyzeError = nil
        analyzeInfo = nil
        isAnalyzingScan = true
        defer { isAnalyzingScan = false }

        let text = (scan.mergedOCRText.isEmpty ? scan.ocrText : scan.mergedOCRText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { analyzeError = "No OCR text to analyze."; return }

        do {
            // Prefer AI; fallback to local
            let parsed: AIAnalysisResponse
            do {
                let result = try await aiService.analyzeWithDebug(ocrText: text)
                parsed = result.parsed
                if let data = try? JSONEncoder().encode(parsed), let s = String(data: data, encoding: .utf8) {
                    scan.aiAnalysisText = s
                }
            } catch {
                let local = localParser.analyze(ocrText: text)
                parsed = local
                if let data = try? JSONEncoder().encode(local), let s = String(data: data, encoding: .utf8) {
                    scan.localAnalysisText = s
                } else {
                    scan.localAnalysisText = String(describing: local)
                }
            }

            // Clear old restrictions linked to this scan
            for r in scan.restrictions { modelContext.delete(r) }
            scan.restrictions.removeAll()

            // Map AIRestriction -> Restriction models and attach
            let now = Date()
            for r in parsed.restrictions {
                let type: RestrictionType
                switch r.type {
                case .no_parking: type = .noParking
                case .street_cleaning: type = .streetCleaning
                case .permit: type = .permit
                case .metered: type = .metered
                default: type = .other
                }

                // Build start/end times
                let (startDate, endDate): (Date, Date) = {
                    if let dur = r.durationMinutes, dur > 0 {
                        let s = now
                        let e = now.addingTimeInterval(TimeInterval(dur * 60))
                        return (s, e)
                    }
                    if let sHM = DateTimeUtils.parseHHmm(r.startTime), let eHM = DateTimeUtils.parseHHmm(r.endTime) {
                        var s = DateTimeUtils.todayAt(hour: sHM.0, minute: sHM.1)
                        var e = DateTimeUtils.todayAt(hour: eHM.0, minute: eHM.1)
                        if e <= s { e = e.addingTimeInterval(24 * 60 * 60) }
                        return (s, e)
                    }
                    let s = DateTimeUtils.todayAt(hour: 0, minute: 0)
                    let e = s.addingTimeInterval(24 * 60 * 60)
                    return (s, e)
                }()

                let restriction = Restriction(
                    type: type,
                    startTime: startDate,
                    endTime: endDate,
                    daysOfWeek: r.daysOfWeek,
                    sourceUser: UUID(),
                    signPhotoFilename: scan.photoFilenames.first ?? scan.photoFilename,
                    ocrText: text,
                    spot: scan.spot,
                    scan: scan
                )
                modelContext.insert(restriction)
                scan.restrictions.append(restriction)
                // Also attach to spot if present so alarms can be scheduled against the spot
                if let spot = scan.spot {
                    spot.restrictions.append(restriction)
                }
            }

            // Compute and store signal state
            let status = ParkingSignalEvaluator.status(for: parsed, now: now, leadMinutes: leadMinutes)
            scan.signalState = status.rawValue
            scan.status = "complete"
            scan.analyzedAt = now
            try? modelContext.save()

            // Schedule alarms/notifications for the spot if linked
            if let spot = scan.spot {
                await NotificationManager.shared.schedule(for: spot.restrictions, spot: spot)
                analyzeInfo = "Analysis complete. Alarms scheduled for this spot."
            } else {
                analyzeInfo = "Analysis complete. Scan not linked to a spot."
            }
        } catch {
            analyzeError = error.localizedDescription
        }
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

#if canImport(UIKit)
    private func loadScanUIImage() -> UIImage? {
        guard let name = scan.photoFilename, !name.isEmpty else { return nil }
        let fm = FileManager.default
        // If an absolute path is provided
        if name.hasPrefix("/") {
            return UIImage(contentsOfFile: name)
        }
        // Try Documents directory
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let url = docs.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                return UIImage(contentsOfFile: url.path)
            }
        }
        // Fallback to bundled asset with the same name
        return UIImage(named: name)
    }
#endif
}

// Helper to map an optional String binding to a non-optional String binding for TextField
extension Binding where Value == String {
    init(_ source: Binding<String?>, replacingNilWith defaultValue: String) {
        self.init(
            get: { source.wrappedValue ?? defaultValue },
            set: { newValue in
                source.wrappedValue = newValue.isEmpty ? nil : newValue
            }
        )
    }
}


#Preview("Edit Scan") {
    let scan = SignScan(
        latitude: 37.7749,
        longitude: -122.4194,
        ocrText: "NO PARKING\nTUE 8AM–10AM\n2 HR PARKING 9AM–6PM MON–FRI"
    )
    return NavigationStack {
        SignScanEditView(scan: scan)
    }
    .modelContainer(for: [SignScan.self], inMemory: true)
}

