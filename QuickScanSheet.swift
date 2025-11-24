// QuickScanSheet.swift
import SwiftUI
import UIKit

struct QuickScanSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var isAnalyzing = false
    @State private var recognizedText: String = ""
    @State private var errorMessage: String?

    private let ocrService = VisionOCRService()

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
                    ScrollView {
                        Text(recognizedText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    HStack {
                        Button {
                            UIPasteboard.general.string = recognizedText
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderedProminent)

                        Spacer()

                        Button("Clear") {
                            recognizedText = ""
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                } else {
                    Text("Tap “Take Photo” to scan text from a sign, document, or anything else.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }

                if let errorMessage {
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
            .navigationTitle("Quick Scan")
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in
                    capturedImage = image
                    Task { await processImage() }
                } onCancel: {
                    isAnalyzing = false
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func processImage() async {
        guard let image = capturedImage else { return }
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }
        do {
            let text = try await ocrService.recognizeText(in: image)
            recognizedText = text
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
