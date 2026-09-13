// QuickScanSheet.swift
import SwiftUI
import UIKit
import UserNotifications
import SwiftData
import CoreLocation
import MapKit

private struct PendingAnalysis: Identifiable {
    let id = UUID()
    let spot: ParkingSpot
    let scanText: String
    let photoFilename: String?
    let analysis: AIAnalysisResponse
}

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
    // Parsed result awaiting the user's confirm/correct before restrictions are saved.
    @State private var pendingAnalysis: PendingAnalysis? = nil

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
                            Task { @MainActor in
                                // Resolve current coordinate and address
                                let coord = locationManager.lastLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                                let geocoder = GeocodingService()
                                let address = await geocoder.reverseGeocode(coordinate: coord)

                                // Find or create the spot (on the main actor)
                                let preferredSide = DrivingSide.storedSide(from: "with")
                                let spot = SpotMergeService.findOrCreateSpot(address: address, coordinate: coord, in: context, preferredSide: preferredSide)

                                // Insert SignScan attached to the spot
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

                                // Assign to nearest segment on the same side (or create)
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

                                // Run AI pipeline (fallback to on-device parser) and attach restrictions to scan and spot
                                var parsed: AIAnalysisResponse
                                do {
                                    parsed = try await aiService.analyze(ocrText: mergedText).parsed
                                } catch {
                                    parsed = localParser.analyze(ocrText: mergedText)
                                }

                                // Present the editable confirmation screen instead of silently
                                // committing possibly-wrong restrictions. Restrictions are created
                                // and alarms scheduled only after the user confirms.
                                await MainActor.run {
                                    recognizedText = mergedText
                                    let status = ParkingSignalEvaluator.status(for: parsed, now: Date(), leadMinutes: leadMinutes)
                                    signalStatus = status
                                    scan.signalState = status.rawValue
                                    scan.status = "complete"
                                    scan.analyzedAt = Date()
                                    try? context.save()

                                    showReview = false
                                    showCamera = false

                                    pendingAnalysis = PendingAnalysis(spot: spot,
                                                                      scanText: mergedText,
                                                                      photoFilename: filenames.first,
                                                                      analysis: parsed)
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
            .sheet(item: $pendingAnalysis) { pending in
                AnalysisConfirmationView(
                    spot: pending.spot,
                    sourceUser: LocalIdentity.userID,
                    ocrText: pending.scanText,
                    photoFilename: pending.photoFilename,
                    analysis: pending.analysis,
                    onFinished: { _ in dismiss() }
                )
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
