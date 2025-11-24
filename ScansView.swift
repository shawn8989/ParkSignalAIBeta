import SwiftUI
import SwiftData

struct SignScanListView: View {
    @Query(sort: \.timestamp, order: .reverse) private var signScans: [SignScan]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            if signScans.isEmpty {
                Text("No sign scans available. Use the scan feature to add new sign scans.")
                    .foregroundColor(.secondary)
                    .padding()
                    .multilineTextAlignment(.center)
            } else {
                List {
                    ForEach(signScans) { signScan in
                        VStack(alignment: .leading) {
                            TextField("OCR Text", text: Binding(
                                get: { signScan.ocrText },
                                set: { newValue in
                                    signScan.ocrText = newValue
                                    modelContext.insert(signScan)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            TextField("Location", text: Binding(
                                get: { signScan.location ?? "" },
                                set: { newValue in
                                    signScan.location = newValue.isEmpty ? nil : newValue
                                    modelContext.insert(signScan)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .swipeActions {
                            Button(role: .destructive) {
                                delete(signScan)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        .navigationTitle("Sign Scans")
        }
    }

    private func delete(_ signScan: SignScan) {
        modelContext.delete(signScan)
        do {
            try modelContext.save()
        } catch {
            print("Failed to delete SignScan: \(error)")
        }
    }
}
