// ParkingSignScannerView.swift
// Continuous live scanner for parking signs with aggregated OCR text.
// - Scans continuously until user explicitly locks/analyzes or cancels.
// - Aggregates recognized text across frames to capture entire sign content.
// - Does NOT auto-stop on partial detections like "NO PARKING".
// - Offers a simple state machine to reflect scanning/analyzing/completed.

import SwiftUI
import VisionKit
import UIKit
import SwiftData

struct ParkingSignScannerView: View {
    // Result handlers provided by the presenting view (e.g., ParkingSpotDetailView)
    // onResult: called with the aggregated text when user taps "Lock & Analyze" (or when auto-stabilized, if enabled)
    // onCancel: called when user taps Cancel
    var onResult: (String, String?) -> Void
    var onCancel: () -> Void
    var onRequestQuickScan: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @AppStorage("alertLeadMinutes") private var leadMinutes: Int = 15

    // Live parsing services
    private let aiService = AIAnalyzerService()
    private let localParser = ParkingTextParser()

    // Live analysis state
    @State private var liveAnalysis: AIAnalysisResponse? = nil
    @State private var liveSignal: ParkingSignalStatus? = nil
    @State private var parseTask: Task<Void, Never>? = nil

    // MARK: - Scanner State Machine
    enum ScannerState { case idle, scanning, analyzing, completed }
    @State private var state: ScannerState = .scanning

    // Latest recognized text for the current frame (from DataScanner)
    @State private var latestFrameText: String = ""

    // Aggregated text composed across frames. We keep a set of lines to avoid duplicates
    // while preserving insertion order with an array.
    @State private var aggregatedLines: [String] = []
    @State private var aggregatedText: String = ""
    @State private var normalizedLineSet: Set<String> = []

    // Stabilization detection: if the aggregatedText remains unchanged for a threshold,
    // we can suggest the user to analyze (or optionally auto-analyze).
    @State private var lastAggregatedSnapshot: String = ""
    @State private var lastChangeTime: Date = Date()
    @State private var hasAutoCommitted = false

    // Photo capture state for saving a still image via CameraPicker
    @State private var showCameraPicker = false
    @State private var capturedImage: UIImage? = nil
    @State private var capturedFilename: String? = nil

    @State private var pendingLockAnalyze: Bool = false

    // Tunables
    private let stabilizationSeconds: TimeInterval = 2.0
    private let autoAnalyzeWhenStable: Bool = false // Prefer explicit user action; set true to auto-commit when stable

    var body: some View {
        NavigationStack {
            ZStack {
                if #available(iOS 16.0, *) {
                    DataScannerContainer(latestText: $latestFrameText)
                        .ignoresSafeArea()
                } else {
                    Text("Live scanning is not supported on this device.")
                        .padding()
                }

                // Overlay controls and status
                VStack {
                    HStack {
                        // Cancel returns without analyzing
                        Button {
                            onCancel()
                            dismiss()
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .font(.title2)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .padding()
                        Spacer()
                    }
                    Spacer()
                    
                    // Banner for quick scan prompt
                    Text("Multiple signs detected? Use Sign Capture to photograph each sign.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            // Live signal and interpreted restriction summary
                            if let sig = liveSignal {
                                HStack(spacing: 8) {
                                    Image(systemName: sig.iconName)
                                        .foregroundStyle(sig.color)
                                    Text(sig.label)
                                        .font(.caption)
                                        .foregroundStyle(sig.color)
                                    Spacer()
                                    if let a = liveAnalysis {
                                        Text("\(a.restrictions.count) restriction(s)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(sig.color.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            // Show a short snippet of the aggregated text so far
                            Text(previewSnippet(aggregatedText))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            // State indicator and stabilization hint
                            HStack(spacing: 8) {
                                Image(systemName: stateIconName())
                                Text(stateLabel())
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                if isStable() {
                                    Text("Ready to analyze")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        Spacer()
                        Button {
                            if let onRequestQuickScan { onRequestQuickScan() } else { showCameraPicker = true }
                        } label: {
                            ZStack {
                                Capsule().fill(.ultraThinMaterial).frame(height: 44)
                                HStack {
                                    Image(systemName: "camera.fill")
                                    Text("Capture Photos to Save This Sign")
                                }
                                .foregroundStyle(.white, .blue)
                                .padding(.horizontal)
                            }
                        }
                        .accessibilityLabel("Save Photo")
                        Button {
                            // Ensure we have a still photo; if not, prompt capture first
                            let cleaned = aggregatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !cleaned.isEmpty else { return }
                            if capturedFilename == nil {
                                // Set a flag to commit after capture
                                pendingLockAnalyze = true
                                showCameraPicker = true
                            } else {
                                state = .analyzing
                                onResult(cleaned, capturedFilename)
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 64, height: 64)
                                Image(systemName: "lock.circle.fill")
                                    .font(.system(size: 56))
                                    .foregroundStyle(.white, .blue)
                                    .accessibilityLabel("Lock & Analyze")
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
            .onChange(of: latestFrameText) { newValue in
                // Merge newly recognized frame text into the aggregated set
                appendToAggregation(newValue)
                // Evaluate stabilization
                evaluateStabilization()
            }
            .onChange(of: aggregatedText) { _ in
                scheduleLiveParse()
            }
            .sheet(isPresented: $showCameraPicker) {
                CameraPicker { image in
                    // Save image via ImageStore and remember filename
                    self.capturedImage = image
                    if let name = try? ImageStore.saveJPEG(image) {
                        self.capturedFilename = name
                    }
                    if self.pendingLockAnalyze {
                        self.pendingLockAnalyze = false
                        self.state = .analyzing
                        let text = self.aggregatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.onResult(text, self.capturedFilename)
                    }
                } onCancel: {
                    // No-op; user dismissed camera without capturing
                }
            }
        }
    }

    // MARK: - Aggregation & Stabilization

    private func appendToAggregation(_ frameText: String) {
        // Normalize: trim, collapse spaces, uppercase for consistent comparison
        let trimmed = frameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Split into lines and normalize each
        let rawLines = trimmed.components(separatedBy: .newlines)
        let normalizedPairs: [(original: String, normalized: String)] = rawLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { original in
                let collapsed = original.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                let upper = collapsed.uppercased()
                return (original: original, normalized: upper)
            }

        var changed = false

        // Update by deduplicating identical lines; preserve insertion order for display
        for pair in normalizedPairs {
            if !normalizedLineSet.contains(pair.normalized) {
                normalizedLineSet.insert(pair.normalized)
                aggregatedLines.append(pair.original)
                changed = true
            } else {
                // If an existing line is shorter than a newer version (e.g., partial -> full), replace it
                if let idx = aggregatedLines.firstIndex(where: { existing in
                    let existingNorm = existing.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).uppercased()
                    return existingNorm == pair.normalized
                }) {
                    let existing = aggregatedLines[idx]
                    if pair.original.count > existing.count {
                        aggregatedLines[idx] = pair.original
                        changed = true
                    }
                }
            }
        }

        if changed {
            // Rebuild aggregatedText from unique lines
            aggregatedText = aggregatedLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            lastAggregatedSnapshot = aggregatedText
            lastChangeTime = Date()
        }
    }

    private func evaluateStabilization() {
        let now = Date()
        let unchangedFor = now.timeIntervalSince(lastChangeTime)
        if unchangedFor >= stabilizationSeconds {
            if autoAnalyzeWhenStable, !hasAutoCommitted {
                hasAutoCommitted = true
                state = .analyzing
                let text = aggregatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                onResult(text, capturedFilename)
            }
        }
    }

    private func isStable() -> Bool {
        // Consider the text stable if it's non-empty and hasn't changed for the stabilization threshold
        let text = aggregatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let unchangedFor = Date().timeIntervalSince(lastChangeTime)
        return unchangedFor >= stabilizationSeconds
    }

    private func scheduleLiveParse() {
        // Debounce frequent updates from the scanner
        parseTask?.cancel()
        let text = aggregatedText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            liveAnalysis = nil
            liveSignal = nil
            return
        }
        parseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s
            await parseLive(text: text)
        }
    }

    @MainActor
    private func parseLive(text: String) async {
        // Prefer AI analyzer; fall back to local parser on failure
        do {
            let result = try await aiService.analyzeWithDebug(ocrText: text)
            self.liveAnalysis = result.parsed
        } catch {
            self.liveAnalysis = localParser.analyze(ocrText: text)
        }
        if let analysis = self.liveAnalysis {
            let status = ParkingSignalEvaluator.status(for: analysis, now: Date(), leadMinutes: leadMinutes)
            self.liveSignal = status
        } else {
            self.liveSignal = nil
        }
    }

    // MARK: - UI helpers

    private func previewSnippet(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "No text yet…" }
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
        let snippet = String(firstLine.prefix(60))
        return snippet + (firstLine.count > 60 ? "…" : "")
    }

    private func stateLabel() -> String {
        switch state {
        case .idle: return "Idle"
        case .scanning: return "Scanning…"
        case .analyzing: return "Analyzing…"
        case .completed: return "Completed"
        }
    }

    private func stateIconName() -> String {
        switch state {
        case .idle: return "pause.circle"
        case .scanning: return "viewfinder.circle"
        case .analyzing: return "bolt.horizontal.circle"
        case .completed: return "checkmark.circle"
        }
    }
}

@available(iOS 16.0, *)
private struct DataScannerContainer: UIViewControllerRepresentable {
    @Binding var latestText: String

    func makeCoordinator() -> Coordinator {
        Coordinator(latestText: $latestText)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [DataScannerViewController.RecognizedDataType.text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        // Ensure scanning is running
        if controller.isScanning == false {
            try? controller.startScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        @Binding var latestText: String

        init(latestText: Binding<String>) {
            _latestText = latestText
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            updateText(from: allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            updateText(from: allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            updateText(from: allItems)
        }

        private func updateText(from items: [RecognizedItem]) {
            // Extract all text blocks from the frame and join with newlines
            var texts: [String] = []
            for item in items {
                if case let .text(obs) = item {
                    texts.append(obs.transcript)
                }
            }
            let joined = texts
                .joined(separator: "\n")
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            DispatchQueue.main.async {
                let norm = joined
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }
                    .joined(separator: "\n")
                self.latestText = norm
            }
        }
    }
}

