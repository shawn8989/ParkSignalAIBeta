import SwiftUI

struct QuickScanReviewView: View {
    let image: UIImage
    var ocrPreview: String?
    var onSubmit: (String, String?) -> Void
    var onRetake: () -> Void
    var onDelete: () -> Void

    @State private var showToast = false
    @State private var working = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ScrollView {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)
                    if let text = ocrPreview, !text.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("OCR Preview")
                                .font(.headline)
                            Text(text)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                        .padding()
                    }
                }
                HStack(spacing: 12) {
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { onRetake() } label: {
                        Label("Retake Photo", systemImage: "arrow.uturn.left")
                    }
                    Spacer()
                    Button {
                        Task { await submit() }
                    } label: {
                        Label("Submit Scan", systemImage: "paperplane")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(working)
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
        }
    }

    private func submit() async {
        guard !working else { return }
        working = true
        defer { working = false }
        var filename: String? = nil
        do {
            filename = try ImageStore.saveJPEG(image)
        } catch {
            // Ignore save failure; proceed without filename
        }
        let text = (ocrPreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { showToast = false }
            onSubmit(text, filename)
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
