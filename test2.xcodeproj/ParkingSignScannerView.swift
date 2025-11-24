// ParkingSignScannerView.swift
import SwiftUI
import VisionKit

struct ParkingSignScannerView: View {
    var onResult: (String) -> Void
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var latestText: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                if #available(iOS 16.0, *) {
                    DataScannerContainer(latestText: $latestText)
                        .ignoresSafeArea()
                } else {
                    Text("Live scanning is not supported on this device.")
                        .padding()
                }

                // Overlay controls
                VStack {
                    HStack {
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
                    HStack {
                        Text(previewSnippet(latestText))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Spacer()
                        Button {
                            onResult(latestText)
                            dismiss()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 64, height: 64)
                                Image(systemName: "camera.circle.fill")
                                    .font(.system(size: 56))
                                    .foregroundStyle(.white, .blue)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func previewSnippet(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "No text yet…" }
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
        return firstLine.prefix(60) + (firstLine.count > 60 ? "…" : "")
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
            recognizedDataTypes: [.text()],
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
        private let keywords = ["no parking", "street", "clean", "sweep", "permit", "meter"]

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
            var texts: [String] = []
            for item in items {
                if case let .text(obs) = item {
                    let t = obs.transcript
                    texts.append(t)
                }
            }
            // Prefer lines that look like parking signage (simple heuristic)
            let joined = texts.joined(separator: "\n")
            let filtered = joined
                .components(separatedBy: .newlines)
                .filter { line in
                    let l = line.lowercased()
                    return keywords.contains(where: { l.contains($0) })
                }
                .joined(separator: "\n")

            DispatchQueue.main.async {
                self.latestText = filtered.isEmpty ? joined : filtered
            }
        }
    }
}
