import SwiftUI

/// Progress, OCR text, parser info and error sections shown during a spot's quick scan.
struct SpotScanStatusSections: View {
    let isAnalyzing: Bool
    let ocrText: String
    let usedAIParsing: Bool?
    let aiFallbackReason: String?
    let scanError: String?

    var body: some View {
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
                        .minimumScaleFactor(0.75)
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
}
