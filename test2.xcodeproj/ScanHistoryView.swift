import SwiftUI
import SwiftData

struct ScanHistoryView: View {
    @Query(sort: \SignScan.createdAt, order: .reverse) private var scans: [SignScan]

    var body: some View {
        NavigationStack {
            List(scans, id: \._persistentIdentifier) { scan in
                HStack(alignment: .top, spacing: 12) {
                    ThumbnailView(filename: scan.photoFilename)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scan.address ?? String(format: "%.5f, %.5f", scan.latitude, scan.longitude))
                            .font(.headline)
                            .lineLimit(1)
                        Text(scan.createdAt, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(scan.status)
                            .font(.caption2)
                            .foregroundColor(scan.status == "complete" ? .green : .orange)
                    }
                }
            }
            .navigationTitle("Scan History")
        }
    }
}

private struct ThumbnailView: View {
    let filename: String?
    var body: some View {
        if let name = filename, let img = ImageStore.loadImage(named: name) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            Image(systemName: "photo").resizable().scaledToFit().foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ScanHistoryView()
        .modelContainer(for: [SignScan.self], inMemory: true)
}
