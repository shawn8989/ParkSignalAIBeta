import SwiftUI
import SwiftData
import MapKit
import CoreLocation

/// The Map Preview and Curb Segment sections of the spot screen.
struct SpotSegmentSections: View {
    @Environment(\.modelContext) private var context
    @Bindable var spot: ParkingSpot
    @Binding var segmentEditScan: SignScan?
    let deviceCoordinate: CLLocationCoordinate2D?
    let presentMap: (CLLocationCoordinate2D, String?) -> Void

    @AppStorage("alertLeadMinutes") private var leadMinutes: Int = 15
    @State private var mapPreviewPosition: MapCameraPosition = .automatic

    var body: some View {
        segmentMapPreviewSection()
        segmentEditorSection()
    }

    private var lastScan: SignScan? {
        spot.signScans.sorted(by: { $0.createdAt > $1.createdAt }).first
    }

    private var spotCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
    }

    @ViewBuilder
    private func segmentMapPreviewSection() -> some View {
        Section(header: Text("Map Preview")) {
            let last = spot.signScans.sorted(by: { $0.createdAt > $1.createdAt }).first
            let center = CLLocationCoordinate2D(
                latitude: last?.segmentCenterLat ?? last?.latitude ?? spot.latitude,
                longitude: last?.segmentCenterLon ?? last?.longitude ?? spot.longitude
            )
            Map(position: $mapPreviewPosition) {
                if let last, let dir = last.segmentDirection ?? last.heading {
                    let pts = CurbGeometry.curbAlignedPolyline(
                        center: center,
                        directionDegrees: dir,
                        sideRaw: last.segmentStreetSide ?? spot.streetSide,
                        lengthMeters: (last.segmentRadius ?? 15) * 2,
                        offsetMeters: 4.5
                    )
                    let status = ParkingSignalEvaluator.status(for: last, now: Date(), leadMinutes: leadMinutes)
                    MapPolyline(coordinates: pts)
                        .stroke(status.color.opacity(0.28), style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: pts)
                        .stroke(status.color, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                } else {
                    MapCircle(center: center, radius: 15)
                        .stroke(Color.accentColor.opacity(0.4), lineWidth: 2)
                        .foregroundStyle(Color.accentColor.opacity(0.08))
                }
                // Spot pin
                Annotation(spot.location, coordinate: CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                        .shadow(radius: 1)
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    Button {
                        presentMap(spotCoordinate, spot.location)
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Button {
                        if let scan = lastScan {
                            segmentEditScan = scan
                        } else {
                            let scan = createOrFetchSegmentScan()
                            segmentEditScan = scan
                        }
                    } label: {
                        Image(systemName: "pencil.and.outline")
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(8)
            }
            .onAppear {
                mapPreviewPosition = .region(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.0025, longitudeDelta: 0.0025)))
            }
        }
    }

    @ViewBuilder
    private func segmentEditorSection() -> some View {
        Section(header: Text("Curb Segment")) {
            if let scan = lastScan {
                VStack(alignment: .leading, spacing: 6) {
                    if let lat = scan.segmentCenterLat, let lon = scan.segmentCenterLon {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin")
                            Text(String(format: "Center: %.5f, %.5f", lat, lon))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin")
                            Text("Center: not set")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.and.right")
                        Text("Side: \((scan.segmentStreetSide ?? spot.streetSide).capitalized)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "ruler")
                        Text("Length: ~\(Int((scan.segmentRadius ?? 15) * 2)) m")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Slider(value: Binding<Double>(
                        get: { (scan.segmentRadius ?? 15) * 2 },
                        set: { newLength in
                            scan.segmentRadius = max(5, newLength / 2)
                            try? context.save()
                        }
                    ), in: 10...100, step: 2)

                    Toggle("Specify Direction", isOn: Binding<Bool>(
                        get: { (scan.segmentDirection ?? scan.heading) != nil },
                        set: { on in
                            if on {
                                // If no explicit direction yet, use existing heading or 0
                                if scan.segmentDirection == nil { scan.segmentDirection = scan.heading ?? 0 }
                            } else {
                                scan.segmentDirection = nil
                            }
                            try? context.save()
                        }
                    ))

                    if (scan.segmentDirection ?? scan.heading) != nil {
                        let dir = (scan.segmentDirection ?? scan.heading ?? 0)
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond")
                            Text("Direction: \(Int(dir))°")
                            Spacer()
                        }
                        Slider(value: Binding<Double>(
                            get: { scan.segmentDirection ?? dir },
                            set: { nv in
                                scan.segmentDirection = CurbGeometry.normalizedHeading(nv)
                                try? context.save()
                            }
                        ), in: 0...360, step: 1)
                    }

                    HStack {
                        Button {
                            // Use scan raw pin as center
                            scan.segmentCenterLat = scan.latitude
                            scan.segmentCenterLon = scan.longitude
                            try? context.save()
                        } label: {
                            Label("Use Scan as Center", systemImage: "mappin")
                        }

                        Spacer()

                        Button {
                            if let c = deviceCoordinate {
                                scan.segmentCenterLat = c.latitude
                                scan.segmentCenterLon = c.longitude
                                try? context.save()
                            }
                        } label: {
                            Label("Use My Location", systemImage: "location")
                        }
                        .disabled(deviceCoordinate == nil)
                    }
                    if deviceCoordinate == nil {
                        Text("Waiting for your location — allow Location access to use “Use My Location”.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Button {
                            segmentEditScan = scan
                        } label: {
                            Label("Edit on Map", systemImage: "pencil.and.outline")
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button(role: .destructive) {
                            clearSegment(for: scan)
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        scan.segmentCenterLat = spot.latitude
                        scan.segmentCenterLon = spot.longitude
                        try? context.save()
                    } label: {
                        Label("Use Spot as Center", systemImage: "mappin.circle")
                    }
                }
            } else {
                Text("No scans yet for this spot.")
                    .foregroundColor(.secondary)
                Button {
                    let scan = createOrFetchSegmentScan()
                    segmentEditScan = scan
                } label: {
                    Label("Create Segment", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @MainActor
    private func createOrFetchSegmentScan() -> SignScan {
        if let scan = lastScan { return scan }
        let coord = spotCoordinate
        let scan = SignScan(
            latitude: coord.latitude,
            longitude: coord.longitude,
            ocrText: "",
            createdAt: Date(),
            photoFilename: nil,
            additionalPhotoFilenames: [],
            photoFilenames: [],
            mergedOCRText: "",
            address: spot.location,
            status: "incomplete",
            sourceUser: LocalIdentity.userID,
            spot: spot,
            segmentCenterLat: coord.latitude,
            segmentCenterLon: coord.longitude,
            segmentRadius: 15.0,
            segmentStreetSide: spot.streetSide
        )
        context.insert(scan)
        spot.attach(scan: scan)
        try? context.save()
        return scan
    }

    private func clearSegment(for scan: SignScan) {
        scan.segmentCenterLat = nil
        scan.segmentCenterLon = nil
        scan.segmentRadius = nil
        scan.segmentDirection = nil
        try? context.save()
    }
}
