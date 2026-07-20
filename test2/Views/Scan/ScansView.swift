import SwiftUI
import SwiftData
import CoreLocation

struct ScansView: View {
    @Environment(\.modelContext) private var context
    @Query private var scans: [SignScan]

    @State private var filterUnattachedOnly: Bool = true
    @State private var editingScan: SignScan?

    var body: some View {
        NavigationStack {
            List {
                if filteredScans.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No \(filterUnattachedOnly ? "unattached" : "") scans yet")
                            .font(.headline)
                        Text("Use the Dashboard scanner to capture street sign text. You can edit or delete scans here.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(filteredScans, id: \.id) { scan in
                        Button {
                            editingScan = scan
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                if let name = scan.photoFilename, let img = ImageStore.loadImage(named: name) {
                                    Image(uiImage: img).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                                } else {
                                    Image(systemName: "photo").resizable().scaledToFit().frame(width: 44, height: 44).foregroundStyle(.secondary)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(scan.address ?? String(format: "%.5f, %.5f", scan.latitude, scan.longitude))
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(scan.ocrText.isEmpty ? "(No text)" : scan.ocrText)
                                        .lineLimit(2)
                                    HStack(spacing: 6) {
                                        Text(scan.createdAt.formatted())
                                        if scan.spot != nil { Text("• Attached") }
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                context.delete(scan)
                                try? context.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Scans")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Picker("Filter", selection: $filterUnattachedOnly) {
                        Text("Unattached").tag(true)
                        Text("All").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                ToolbarItem(placement: .primaryAction) {
                    if !filteredScans.isEmpty {
                        Button(role: .destructive) {
                            deleteAllFiltered()
                        } label: {
                            Label("Delete Filtered", systemImage: "trash")
                        }
                    }
                }
            }
            .sheet(item: $editingScan) { scan in
                SignScanEditView(scan: scan)
                    .environment(\.modelContext, context)
            }
        }
    }

    private var filteredScans: [SignScan] {
        if filterUnattachedOnly {
            return scans.filter { $0.spot == nil }.sorted { $0.createdAt > $1.createdAt }
        } else {
            return scans.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private func deleteAllFiltered() {
        let targets = filteredScans
        for s in targets { context.delete(s) }
        try? context.save()
    }
}

#Preview {
    ScansView()
        .modelContainer(for: [ParkingSpot.self, SignScan.self], inMemory: true)
}
