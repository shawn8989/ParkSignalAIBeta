import SwiftUI

/// Progress, OCR text, parser info and error sections shown during a spot's quick scan.
struct SpotScanStatusSections: View {
    let isAnalyzing: Bool
    let ocrText: String
    let scanError: String?

    var body: some View {
        if isAnalyzing {
            analyzingSection()
        }
        if !ocrText.isEmpty {
            lastOCRSection()
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
    private func scanErrorSection() -> some View {
        if let scanError {
            Section {
                Text(scanError)
                    .foregroundColor(.red)
            }
        }
    }
}
