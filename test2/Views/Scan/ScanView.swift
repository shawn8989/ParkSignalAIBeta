import SwiftUI
import SwiftData
import CoreLocation
import UIKit

/// The home tab: capture a parking sign, get an instant color-coded verdict, then save the spot.
struct ScanView: View {
    @StateObject private var locationManager = LocationManager()

    @State private var showCamera = false
    @State private var showLiveScanner = false
    @State private var isAnalyzing = false
    @State private var result: ScanResult?
    @State private var errorMessage: String?
    @State private var showConfirmation = false

    private let ocrService = VisionOCRService()
    private let aiService = AIAnalyzerService()
    private let parser = ParkingTextParser()
    private let geocoder = GeocodingService()

    struct ScanResult {
        var ocrText: String
        var analysis: AIAnalysisResponse
        var aiRefined: Bool
        var photoFilename: String?
        var latitude: Double
        var longitude: Double
        var address: String
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ActiveSessionBanner()

                if let result {
                    VerdictView(
                        result: result,
                        onSave: { showConfirmation = true },
                        onNewScan: { self.result = nil }
                    )
                } else {
                    idleContent
                }
            }
            .navigationTitle("ParkSignal")
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in
                    Task { await process(image: image) }
                } onCancel: { }
            }
            .sheet(isPresented: $showLiveScanner) {
                ParkingSignScannerView { text in
                    Task { await process(ocrText: text, image: nil) }
                } onCancel: { }
            }
            .sheet(isPresented: $showConfirmation) {
                if let result {
                    AnalysisConfirmationView(
                        ocrText: result.ocrText,
                        photoFilename: result.photoFilename,
                        analysis: result.analysis,
                        latitude: result.latitude,
                        longitude: result.longitude,
                        address: result.address,
                        onFinished: { self.result = nil }
                    )
                }
            }
            .onAppear {
                if locationManager.authorizationStatus == .notDetermined {
                    locationManager.requestWhenInUseAuthorization()
                }
            }
        }
    }

    private var idleContent: some View {
        VStack(spacing: 24) {
            Spacer()

            if isAnalyzing {
                ProgressView("Reading sign…")
                    .controlSize(.large)
            } else {
                Image(systemName: "parkingsign.circle.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(.tint)
                Text("Scan a parking sign")
                    .font(.title2.bold())
                Text("Snap a photo of any parking sign and get an instant answer: can you park here right now?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    errorMessage = nil
                    showCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAnalyzing)

                Button {
                    errorMessage = nil
                    showLiveScanner = true
                } label: {
                    Label("Live Scan", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(isAnalyzing)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    // MARK: - Pipeline

    private func process(image: UIImage) async {
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }
        do {
            let text = try await ocrService.recognizeText(in: image)
            await process(ocrText: text, image: image)
        } catch {
            errorMessage = "Couldn't read the photo: \(error.localizedDescription)"
        }
    }

    private func process(ocrText: String, image: UIImage?) async {
        let trimmed = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "No text detected. Get closer to the sign and try again."
            return
        }

        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }

        let filename = image.flatMap { try? ImageStore.saveJPEG($0) }
        let coordinate = locationManager.lastLocation?.coordinate
        var address = ""
        if let coordinate {
            address = await geocoder.reverseGeocode(coordinate: coordinate)
        }

        // Instant on-device parse — works offline, no key needed.
        let localAnalysis = parser.analyze(ocrText: trimmed)
        result = ScanResult(
            ocrText: trimmed,
            analysis: localAnalysis,
            aiRefined: false,
            photoFilename: filename,
            latitude: coordinate?.latitude ?? 0,
            longitude: coordinate?.longitude ?? 0,
            address: address
        )

        // Upgrade with AI when a key is configured; the local result stays if this fails.
        guard AIAnalyzerService.isConfigured else { return }
        do {
            let (refined, _) = try await aiService.analyze(ocrText: trimmed)
            if result?.ocrText == trimmed, !refined.restrictions.isEmpty {
                result?.analysis = refined
                result?.aiRefined = true
            }
        } catch {
            // Keep the on-device result; AI refinement is best-effort.
        }
    }
}

// MARK: - Verdict

private struct VerdictView: View {
    let result: ScanView.ScanResult
    let onSave: () -> Void
    let onNewScan: () -> Void

    private var status: ParkingSignalStatus {
        ParkingSignalEvaluator.status(
            for: result.analysis,
            leadMinutes: UserDefaults.standard.integer(forKey: "alertLeadMinutes") == 0
                ? 15
                : UserDefaults.standard.integer(forKey: "alertLeadMinutes")
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    Image(systemName: status.iconName)
                        .font(.system(size: 56))
                    Text(status.label)
                        .font(.title.bold())
                    Text(result.aiRefined ? "AI-refined analysis" : "On-device analysis")
                        .font(.caption)
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(status.color.gradient, in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal)

                if !result.address.isEmpty {
                    Label(result.address, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if result.analysis.restrictions.isEmpty {
                    ContentUnavailableView(
                        "No restrictions recognized",
                        systemImage: "questionmark.circle",
                        description: Text("The sign text was read but no rules could be parsed:\n\n\(result.ocrText)")
                    )
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Detected rules")
                            .font(.headline)
                        ForEach(Array(result.analysis.restrictions.enumerated()), id: \.offset) { _, r in
                            RestrictionRow(restriction: r)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    Button {
                        onSave()
                    } label: {
                        Label("Save This Spot", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(result.analysis.restrictions.isEmpty)

                    Button {
                        onNewScan()
                    } label: {
                        Label("New Scan", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .padding(.top)
        }
    }
}

private struct RestrictionRow: View {
    let restriction: AIRestriction

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text("\(daysText) • \(restriction.startTime)–\(restriction.endTime)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let notes = restriction.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var title: String {
        switch restriction.type {
        case .street_cleaning: return "Street Cleaning"
        case .no_parking: return "No Parking"
        case .metered: return "Metered"
        case .permit: return "Permit Required"
        case .other: return "Other Restriction"
        }
    }

    private var icon: String {
        switch restriction.type {
        case .street_cleaning: return "bubbles.and.sparkles"
        case .no_parking: return "nosign"
        case .metered: return "dollarsign.circle"
        case .permit: return "person.badge.shield.checkmark"
        case .other: return "info.circle"
        }
    }

    private var daysText: String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let labels = restriction.daysOfWeek.compactMap { (0...6).contains($0) ? symbols[$0] : nil }
        return labels.isEmpty ? "Every day" : labels.joined(separator: ", ")
    }
}

// MARK: - Active session banner

/// Shows "Parked at … for …" whenever a ParkSession is active, with a quick way to end it.
struct ActiveSessionBanner: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ParkSession> { $0.endedAt == nil }) private var activeSessions: [ParkSession]

    var body: some View {
        if let session = activeSessions.first {
            HStack(spacing: 12) {
                Image(systemName: "car.fill")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Parked at \(session.spot?.location ?? "Unknown spot")")
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Text(session.startedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("End") {
                    session.endedAt = .now
                    try? context.save()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.thinMaterial)
        }
    }
}
