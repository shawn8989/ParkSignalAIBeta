import SwiftUI
import SwiftData
import CoreLocation

struct ScanHistoryView: View {
    @Query(sort: \SignScan.createdAt, order: .reverse) private var scans: [SignScan]

    var body: some View {
        NavigationStack {
            List(scans, id: \._persistentIdentifier) { scan in
                NavigationLink {
                    if let spot = scan.spot {
                        ParkingSpotDetailView(spot: spot)
                    } else {
                        ResumeScanView(scan: scan)
                    }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        ThumbnailsStripView(filenames: scan.photoFilenames.isEmpty ? (scan.photoFilename.map { [$0] } ?? []) : scan.photoFilenames)
                        VStack(alignment: .leading, spacing: 4) {
                            AddressText(scan: scan)
                                .font(.headline)
                                .lineLimit(1)
                            Text(scan.createdAt, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(scan.status)
                                .font(.caption2)
                                .foregroundColor(scan.status == "complete" ? .green : .orange)
                            let status = ParkingSignalEvaluator.status(for: scan, now: Date(), leadMinutes: 15)
                            HStack(spacing: 6) {
                                Image(systemName: status.iconName)
                                Text(status.label)
                            }
                            .font(.caption)
                            .foregroundStyle(status.color)
                        }
                    }
                }
            }
            .navigationTitle("Scan History")
        }
    }
}

private struct AddressText: View {
    @Environment(\.modelContext) private var context
    let scan: SignScan
    @State private var resolved: String? = nil

    var body: some View {
        Text(resolved ?? scan.address ?? String(format: "%.5f, %.5f", scan.latitude, scan.longitude))
            .task(id: scan._persistentIdentifier) {
                if (scan.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let coord = CLLocationCoordinate2D(latitude: scan.latitude, longitude: scan.longitude)
                    let addr = await reverseGeocode(coord)
                    await MainActor.run {
                        self.resolved = addr
                        if let a = addr, !a.isEmpty {
                            scan.address = a
                            try? context.save()
                        }
                    }
                } else {
                    resolved = scan.address
                }
            }
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> String? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if let p = placemarks.first {
                let parts = [p.name, p.locality, p.administrativeArea].compactMap { $0 }.filter { !$0.isEmpty }
                if !parts.isEmpty { return parts.joined(separator: ", ") }
            }
            return nil
        } catch {
            return nil
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

private struct ResumeScanView: View {
    let scan: SignScan
    @Environment(\.modelContext) private var context
    @State private var resolvedAddress: String? = nil
    var body: some View {
        List {
            Section("Scan Details") {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(scan.status)
                        .foregroundStyle(scan.status == "complete" ? .green : .orange)
                }
                HStack {
                    Text("Created")
                    Spacer()
                    Text(scan.createdAt, style: .date)
                }
                HStack(alignment: .top) {
                    Text("Address")
                    Spacer()
                    Text(resolvedAddress ?? scan.address ?? String(format: "%.5f, %.5f", scan.latitude, scan.longitude))
                        .multilineTextAlignment(.trailing)
                }
            }
            Section("OCR Text") {
                Text(scan.mergedOCRText.isEmpty ? scan.ocrText : scan.mergedOCRText)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            if !scan.photoFilenames.isEmpty {
                Section("Photos") {
                    ThumbnailsStripView(filenames: scan.photoFilenames)
                }
            } else if let name = scan.photoFilename {
                Section("Photo") {
                    if let img = ImageStore.loadImage(named: name) {
                        Image(uiImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.15))
                            Image(systemName: "photo")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.secondary)
                                .padding(24)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                    }
                }
            }
            Section {
                if scan.spot != nil {
                    Text("Open the associated spot to resume analysis.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("This scan is not linked to a spot yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Scan")
        .onAppear {
            if (scan.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task {
                    let address = await reverseGeocode(CLLocationCoordinate2D(latitude: scan.latitude, longitude: scan.longitude))
                    await MainActor.run {
                        self.resolvedAddress = address
                        if let addr = address, !addr.isEmpty {
                            scan.address = addr
                            try? context.save()
                        }
                    }
                }
            } else {
                resolvedAddress = scan.address
            }
        }
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> String? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if let p = placemarks.first {
                let parts = [p.name, p.locality, p.administrativeArea].compactMap { $0 }.filter { !$0.isEmpty }
                if !parts.isEmpty { return parts.joined(separator: ", ") }
            }
            return nil
        } catch {
            return nil
        }
    }
}

private struct ThumbnailsStripView: View {
    let filenames: [String]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filenames, id: \.self) { name in
                    if let img = ImageStore.loadImage(named: name) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15))
                            Image(systemName: "photo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 64, height: 64)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    ScanHistoryView()
        .modelContainer(for: [SignScan.self], inMemory: true)
}

