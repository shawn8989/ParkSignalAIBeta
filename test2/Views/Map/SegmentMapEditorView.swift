import SwiftUI
import MapKit
import CoreLocation
import SwiftData

struct SegmentMapEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var scan: SignScan

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var settingDirection: Bool = false
    @State private var editingRawPin: Bool = false

    @State private var segSide: StreetSide = .right
    @State private var segRadius: Double = 15
    @State private var segDirection: Double? = nil
    @State private var lastRawPinSide: StreetSide? = nil
    @State private var haptic = UIImpactFeedbackGenerator(style: .light)
    
    @State private var dragStartPoint: CGPoint? = nil
    @State private var lastSnappedSide: StreetSide? = nil

    private var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: scan.segmentCenterLat ?? scan.latitude,
            longitude: scan.segmentCenterLon ?? scan.longitude
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        // Draw ribbon if we have a direction, else a circle
                        if let dir = segDirection ?? scan.segmentDirection ?? scan.heading {
                            let pts = CurbGeometry.curbAlignedPolyline(
                                center: center,
                                directionDegrees: dir,
                                sideRaw: scan.segmentStreetSide ?? scan.spot?.streetSide,
                                lengthMeters: 20.0,
                                offsetMeters: 4.5
                            )
                            MapPolyline(coordinates: pts)
                                .stroke(Color.accentColor.opacity(0.28), style: StrokeStyle(lineWidth: 26, lineCap: .round, lineJoin: .round))
                            MapPolyline(coordinates: pts)
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                        } else {
                            MapCircle(center: center, radius: segRadius)
                                .stroke(Color.accentColor.opacity(0.4), lineWidth: 2)
                                .foregroundStyle(Color.accentColor.opacity(0.08))
                        }

                        // Center marker
                        Annotation("Segment Center", coordinate: center) {
                            ZStack {
                                Circle().fill(Color.accentColor).frame(width: 16, height: 16)
                                Circle().stroke(Color.white, lineWidth: 2).frame(width: 16, height: 16)
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if dragStartPoint == nil { dragStartPoint = proxy.convert(center, to: .local) }
                                        guard let base = dragStartPoint else { return }
                                        let newPoint = CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height)
                                        if let newCoord = proxy.convert(newPoint, from: .local) {
                                            scan.segmentCenterLat = newCoord.latitude
                                            scan.segmentCenterLon = newCoord.longitude

                                            if let d = segDirection ?? scan.segmentDirection ?? scan.heading {
                                                let R = 6_371_000.0
                                                let lat0 = center.latitude * .pi/180
                                                let dx = (newCoord.longitude - center.longitude) * cos(lat0) * R
                                                let dy = (newCoord.latitude - center.latitude) * R
                                                let theta = d * .pi/180
                                                let vx = sin(theta)
                                                let vy = cos(theta)
                                                let z = vx * dy - vy * dx
                                                let inferred: StreetSide = (z > 0) ? .left : .right
                                                if inferred.rawValue != (scan.segmentStreetSide ?? scan.spot?.streetSide ?? "") {
                                                    scan.segmentStreetSide = inferred.rawValue
                                                    haptic.impactOccurred()
                                                }
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        dragStartPoint = nil
                                        try? context.save()
                                    }
                            )
                        }
                        
                        if editingRawPin {
                            Annotation("Sign Pin", coordinate: CLLocationCoordinate2D(latitude: scan.latitude, longitude: scan.longitude)) {
                                let size: CGFloat = 16
                                ZStack {
                                    Rectangle()
                                        .fill(Color.orange)
                                        .frame(width: size, height: size)
                                        .rotationEffect(.degrees(45))
                                        .overlay(Rectangle().stroke(Color.white, lineWidth: 2).rotationEffect(.degrees(45)))
                                        .shadow(radius: 1)
                                }
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            // Start from the current raw pin screen point
                                            guard let start = proxy.convert(CLLocationCoordinate2D(latitude: scan.latitude, longitude: scan.longitude), to: .local) else { return }
                                            let newPoint = CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height)
                                            guard let newCoord = proxy.convert(newPoint, from: .local) else { return }
                                            var adjusted = newCoord
                                            // Snap-to-street assist: if we have a direction and a segment center, snap near the curb offset
                                            if let d = segDirection ?? scan.segmentDirection ?? scan.heading,
                                               let cLat = scan.segmentCenterLat ?? scan.latitude as Double?,
                                               let cLon = scan.segmentCenterLon ?? scan.longitude as Double? {
                                                let centerCoord = CLLocationCoordinate2D(latitude: cLat, longitude: cLon)
                                                // Infer side from cross product
                                                let R = 6_371_000.0
                                                let lat0 = centerCoord.latitude * .pi/180
                                                let dx = (newCoord.longitude - centerCoord.longitude) * cos(lat0) * R
                                                let dy = (newCoord.latitude - centerCoord.latitude) * R
                                                let theta = d * .pi/180
                                                let vx = sin(theta)
                                                let vy = cos(theta)
                                                let z = vx * dy - vy * dx
                                                let inferred: StreetSide = (z > 0) ? .left : .right
                                                if inferred != lastRawPinSide {
                                                    haptic.impactOccurred()
                                                    lastRawPinSide = inferred
                                                }
                                                scan.segmentStreetSide = inferred.rawValue
                                                // If close to center (< 8m), snap exactly to curb offset (4.5m) on inferred side
                                                let dist = SegmentUtils.distanceMeters(centerCoord, newCoord)
                                                if dist < 8.0 {
                                                    let perp = inferred == .left ? CurbGeometry.normalizedHeading(d - 90) : CurbGeometry.normalizedHeading(d + 90)
                                                    let snapped = CurbGeometry.coordinate(from: centerCoord, bearingDegrees: perp, distanceMeters: 4.5)
                                                    adjusted = snapped
                                                }
                                            }
                                            scan.latitude = adjusted.latitude
                                            scan.longitude = adjusted.longitude
                                        }
                                        .onEnded { _ in
                                            try? context.save()
                                        }
                                )
                            }
                        }
                    }
                    .highPriorityGesture(
                        SpatialTapGesture(count: 1).onEnded { value in
                            let point = value.location
                            if let coord = proxy.convert(point, from: .local) {
                                if settingDirection {
                                    let dir = SegmentUtils.bearingDegrees(from: center, to: coord)
                                    segDirection = CurbGeometry.normalizedHeading(dir)
                                    scan.segmentDirection = segDirection
                                    settingDirection = false
                                } else {
                                    scan.segmentCenterLat = coord.latitude
                                    scan.segmentCenterLon = coord.longitude
                                }
                                try? context.save()
                                recenter()
                            }
                        }
                    )
                    .overlay(alignment: .bottomLeading) {
                        Text("Tip: Drag the center dot to move. It will snap to the street side.")
                            .font(.caption2)
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                    }
                    .onAppear {
                        // Initialize state from scan values
                        segSide = StreetSide(rawValue: (scan.segmentStreetSide ?? scan.spot?.streetSide ?? "right").lowercased()) ?? .right
                        segRadius = scan.segmentRadius ?? 15
                        segDirection = scan.segmentDirection ?? scan.heading
                        recenter()
                    }
                    .frame(height: 300)
                }

                Form {
                    Section("Segment") {
                        Picker("Side", selection: $segSide) {
                            Text("Left").tag(StreetSide.left)
                            Text("Right").tag(StreetSide.right)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: segSide) { newValue in
                            scan.segmentStreetSide = newValue.rawValue
                            try? context.save()
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "ruler")
                            Text("Radius: ~\(Int(segRadius)) m")
                            Spacer()
                        }
                        Slider(value: $segRadius, in: 5...50, step: 1) { _ in
                            scan.segmentRadius = segRadius
                            try? context.save()
                        }

                        Toggle("Tap to set direction", isOn: $settingDirection)
                        
                        Toggle("Edit Raw Sign Pin", isOn: $editingRawPin)

                        Toggle("Sync Segment Center to Sign Pin", isOn: Binding(get: {
                            if let lat = scan.segmentCenterLat, let lon = scan.segmentCenterLon {
                                return abs(lat - scan.latitude) < 0.00001 && abs(lon - scan.longitude) < 0.00001
                            }
                            return false
                        }, set: { on in
                            if on {
                                scan.segmentCenterLat = scan.latitude
                                scan.segmentCenterLon = scan.longitude
                                try? context.save()
                            }
                        }))

                        if let d = segDirection {
                            HStack {
                                Text("Direction: \(Int(d))°")
                                Spacer()
                                Button("Clear") {
                                    segDirection = nil
                                    scan.segmentDirection = nil
                                    try? context.save()
                                }
                            }
                            Slider(value: Binding(get: { segDirection ?? 0 }, set: { newVal in
                                segDirection = newVal
                                scan.segmentDirection = newVal
                                try? context.save()
                            }), in: 0...360, step: 1)
                        } else {
                            Button {
                                segDirection = 0
                                scan.segmentDirection = 0
                                try? context.save()
                            } label: {
                                Label("Enable Direction Slider", systemImage: "arrow.triangle.turn.up.right.diamond")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Segment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { try? context.save(); dismiss() } }
            }
        }
    }

    private func recenter() {
        let c = center
        cameraPosition = .region(
            MKCoordinateRegion(
                center: c,
                span: MKCoordinateSpan(latitudeDelta: 0.0025, longitudeDelta: 0.0025)
            )
        )
    }
}
