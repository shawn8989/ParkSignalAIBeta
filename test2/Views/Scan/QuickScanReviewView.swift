import SwiftUI
import UIKit
import SwiftData

struct QuickScanReviewView: View {
    @Environment(\.modelContext) private var context
    // Initial seed image/OCR (optional). The view manages a multi‑photo session.
    let image: UIImage
    var ocrPreview: String?

    // New multi‑photo submit: merged OCR text and ordered filenames
    var onSubmit: (String, [String]) -> Void
    var onRetake: () -> Void
    var onDelete: () -> Void

    @State private var images: [UIImage] = []
    @State private var ocrTexts: [String] = []

    @State private var showToast = false
    @State private var working = false
    @State private var saveError: String?
    @State private var showingCamera = false

    private let ocrService = VisionOCRService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let saveError { Text(saveError).foregroundStyle(.red).padding() }
                ScrollView {
                    VStack(spacing: 12) {
                        if let last = images.last {
                            Image(uiImage: last)
                                .resizable()
                                .accessibilityLabel("Selected sign photo")
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding(.horizontal)
                        }

                        // Thumbnails strip
                        if images.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(images.indices, id: \.self) { idx in
                                        Image(uiImage: images[idx])
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 72, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(alignment: .topTrailing) {
                                                if idx == images.count - 1 {
                                                    Text("Latest")
                                                        .font(.system(size: 9))
                                                        .padding(4)
                                                        .background(.ultraThinMaterial)
                                                        .clipShape(Capsule())
                                                        .padding(4)
                                                }
                                            }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }

                        if !mergedOCRText.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("OCR Preview")
                                    .font(.headline)
                                Text(mergedOCRText)
                                    .font(.body.monospaced())
                                    .textSelection(.enabled)
                            }
                            .padding()
                        }
                    }
                }

                VStack(spacing: 10) {
                    Menu {
                        Button("Retake Photo", systemImage: "arrow.uturn.left", action: onRetake)
                        Button("Add Another Photo", systemImage: "plus.circle") { showingCamera = true }
                        Button("Discard Photos", systemImage: "trash", role: .destructive, action: onDelete)
                    } label: {
                        Label("Photo Options", systemImage: "ellipsis.circle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        Task { await submit() }
                    } label: {
                        Label("Review Rules", systemImage: "checklist")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(working || mergedOCRText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if mergedOCRText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("No sign text was found. Retake a clearer photo or enter a rule manually from the spot.").font(.footnote)
                    }
                }
                .padding()
            }
            .navigationTitle("Review Scan")
            .overlay(alignment: .top) {
                if showToast {
                    ToastView(text: "Sign scanned successfully")
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPicker { newImage in
                    Task { await addImage(newImage) }
                } onCancel: { }
            }
            .onAppear {
                // Seed arrays from initial inputs
                if images.isEmpty { images = [image] }
                if ocrTexts.isEmpty { ocrTexts = [ocrPreview ?? ""] }
                Task {
                    // Ensure we have OCR for the initial image if not provided
                    if (ocrPreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if let first = images.first {
                            let text = (try? await ocrService.recognizeText(in: first)) ?? ""
                            await MainActor.run { if ocrTexts.isEmpty { ocrTexts = [text] } else { ocrTexts[0] = text } }
                        }
                    }
                }
            }
        }
    }

    // Centralized OCR merging and deduplication
    private var mergedOCRText: String {
        OCRTextUtils.mergeAndDeduplicate(blocks: ocrTexts)
    }

    @MainActor
    private func addImage(_ newImage: UIImage) async {
        images.append(newImage)
        // OCR asynchronously; append placeholder first to keep indices aligned
        ocrTexts.append("")
        if let idx = images.indices.last {
            let text = (try? await ocrService.recognizeText(in: newImage)) ?? ""
            ocrTexts[idx] = text
        }
    }

    private func submit() async {
        guard !working else { return }
        working = true
        defer { working = false }
        var filenames: [String] = []
        for img in images {
            do { filenames.append(try ImageStore.saveJPEG(img, context: context)) }
            catch { saveError = "Couldn't save the photos: \(error.localizedDescription)"; return }
        }
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { showToast = false }
            onSubmit(mergedOCRText, filenames)
        }
    }
}

private struct ToastView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(.top, 8)
    }
}
