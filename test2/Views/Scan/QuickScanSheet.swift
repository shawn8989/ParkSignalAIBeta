// QuickScanSheet.swift
import SwiftUI
import UIKit
import UserNotifications
import SwiftData
import CoreLocation
import MapKit

struct QuickScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var showCamera = false
    @State private var showReview = false
    @State private var capturedImage: UIImage?
    @State private var pendingOCRPreview: String? = nil
    @State private var pendingImage: UIImage? = nil
    @State private var isAnalyzing = false
    @State private var recognizedText: String = ""
    @State private var errorMessage: String?
    @State private var signalStatus: ParkingSignalStatus = .gray
    @AppStorage("alertLeadMinutes") private var leadMinutes: Int = 15

    @StateObject private var locationManager = LocationManager()
    @State private var photoFilename: String? = nil
    // Newly created or matched spot to edit after saving scan
    @State private var newSpotForEdit: ParkingSpot? = nil

    private let ocrService = VisionOCRService()
    private let aiService = AIAnalyzerService()
    private let localParser = ParkingTextParser()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if isAnalyzing {
                    HStack {
                        ProgressView()
                        Text("Scanning…")
                    }
                }

                if !recognizedText.isEmpty {
                    HStack {
                        Image(systemName: signalStatus.iconName)
                            .foregroundStyle(signalStatus.color)
                        Text(signalStatus.label)
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(signalStatus.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if !recognizedText.isEmpty {
                    ScrollView {
                        Text(recognizedText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    ButtonsRow(
                        recognizedText: $recognizedText,
                        onAnalyze: { Task { await analyzeRecognizedText(useAI: false) } },
                        onClear: { recognizedText = "" }
                    )
                    .padding(.horizontal)
                }

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                Spacer()

                Button {
                    showCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            .navigationTitle("Sign Capture")
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in
                    capturedImage = image
                    Task { await processImage() }
                } onCancel: {
                    isAnalyzing = false
                }
            }
            .sheet(isPresented: $showReview) {
                if let img = pendingImage {
                    QuickScanReviewView(
                        image: img,
                        ocrPreview: pendingOCRPreview,
                        onSubmit: { mergedText, filenames in
                            Task {
                                // Resolve current coordinate and address
                                let coord = locationManager.lastLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                                let geocoder = GeocodingService()
                                let address = await geocoder.reverseGeocode(coordinate: coord)

                                // Use SpotMergeService to find or create spot
                                let spot = await MainActor.run { () -> ParkingSpot in
                                    let preferredSide = DrivingSide.storedSide(from: "with")
                                    return SpotMergeService.findOrCreateSpot(address: address, coordinate: coord, in: context, preferredSide: preferredSide)
                                }

                                // Insert SignScan attached to the spot
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
                                        address: address.isEmpty ? nil : address,
                                        status: "incomplete",
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

                                // Assign to nearest segment on the same side (or create)
                                await MainActor.run {
                                    let allScans = (try? context.fetch(FetchDescriptor<SignScan>())) ?? []
                                    let loc = CLLocationCoordinate2D(latitude: scan.latitude, longitude: scan.longitude)
                                    _ = SegmentManager.assign(
                                        scan: scan,
                                        existingScans: allScans.filter { $0.id != scan.id },
                                        currentLocation: loc,
                                        heading: scan.heading,
                                        preferredSide: StreetSide(rawValue: spot.streetSide.lowercased()),
                                        defaultRadius: 15.0
                                    )
                                    try? context.save()
                                }

                                // Run AI pipeline (fallback to on-device parser) and attach restrictions to scan and spot
                                var parsed: AIAnalysisResponse
                                do {
                                    parsed = try await aiService.analyze(ocrText: mergedText).parsed
                                } catch {
                                    parsed = localParser.analyze(ocrText: mergedText)
                                }

                                // Map AIRestriction -> Restriction models, attach to scan and spot
                                await MainActor.run {
                                    recognizedText = mergedText
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
                                                let s = DateTimeUtils.todayAt(hour: sHM.0, minute: sHM.1)
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
                                            signPhotoFilename: filenames.first,
                                            ocrText: mergedText,
                                            spot: spot,
                                            scan: scan
                                        )
                                        context.insert(restriction)
                                        scan.restrictions.append(restriction)
                                        spot.restrictions.append(restriction)
                                    }

                                    // Compute and store signal state
                                    let status = ParkingSignalEvaluator.status(for: parsed, now: now, leadMinutes: leadMinutes)
                                    signalStatus = status
                                    scan.signalState = status.rawValue
                                    scan.status = "complete"
                                    scan.analyzedAt = now
                                    try? context.save()

                                    // Close review/camera flow
                                    showReview = false
                                    showCamera = false

                                    // Present spot edit for confirmation/adjustments
                                    newSpotForEdit = spot
                                }
                            }
                        },
                        onRetake: {
                            showReview = false
                            showCamera = true
                        },
                        onDelete: {
                            showReview = false
                            showCamera = false
                            pendingImage = nil
                            pendingOCRPreview = nil
                        }
                    )
                }
            }
            .sheet(item: $newSpotForEdit) { spot in
                SpotEditView(spot: spot)
                    .environment(\.modelContext, context)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            } else if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                locationManager.startUpdatingLocation()
            }
        }
        .onDisappear {
            locationManager.stopUpdatingLocation()
        }
    }

    private func normalized(_ s: String?) -> String {
        return (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func processImage() async {
        guard let image = capturedImage else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }
        pendingImage = image
        // Precompute a quick OCR preview (non-blocking for UX)
        let preview = try? await ocrService.recognizeText(in: image)
        await MainActor.run {
            pendingOCRPreview = preview
            showReview = true
        }
    }

    @MainActor
    private func analyzeRecognizedText(useAI: Bool) async {
        guard !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }

        let parsed: AIAnalysisResponse
        if useAI, let aiResult = try? await aiService.analyze(ocrText: recognizedText) {
            parsed = aiResult.parsed
        } else {
            parsed = localParser.analyze(ocrText: recognizedText)
        }
        signalStatus = ParkingSignalEvaluator.status(for: parsed, now: Date(), leadMinutes: leadMinutes)
    }

}

private struct ButtonsRow: View {
    @Binding var recognizedText: String
    var onAnalyze: () -> Void
    var onClear: () -> Void

    var body: some View {
        HStack {
            Button {
                UIPasteboard.general.string = recognizedText
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Analyze", action: onAnalyze)
                .buttonStyle(.borderedProminent)

            Button("Clear", action: onClear)
                .buttonStyle(.bordered)
        }
    }
}
