import SwiftUI
import MapKit
import CoreLocation
import SwiftData
import UIKit
import Combine

struct MapView: View {
    var spots: [ParkingSpot]
    var userCoordinate: CLLocationCoordinate2D?

    @Binding var cameraPosition: MapCameraPosition
    var tempPin: CLLocationCoordinate2D?
    var onAddPinAtCoordinate: (CLLocationCoordinate2D) -> Void
    var onSelectSpot: (ParkingSpot) -> Void
    var showAvailabilityOverlay: Bool = true
    var showLegend: Bool = true
    var showCityZoneOverlay: Bool = true

    @Query private var scans: [SignScan]
    @Query private var sessions: [ParkSession]    // <- Added this line
    @Environment(\.modelContext) private var _modelContext
    @State private var selectedScan: SignScan? = nil

    @State private var cityOverlays: [ZoneOverlay] = []
    @AppStorage("alertLeadMinutes") private var leadMinutes: Int = 15
    @State private var now: Date = Date()
    
    @State private var isEditingSegments: Bool = false
    @State private var editingScanID: UUID? = nil

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                
                if showAvailabilityOverlay {
                    ForEach(spots, id: \.id) { spot in
                        MapCircle(
                            center: CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude),
                            radius: 60
                        )
                        .foregroundStyle(signalColor(for: spot).opacity(0.18))
                    }
                }
                
                if showCityZoneOverlay {
                    ForEach(cityOverlays, id: \.self) { overlay in
                        MapCircle(center: overlay.center, radius: overlay.radiusMeters)
                            .stroke(Color.blue.opacity(0.4), lineWidth: 2)
                            .foregroundStyle(Color.blue.opacity(0.08))
                    }
                }
                
                // Street sign scans: curb-aligned ribbons + unique scan pins
                ForEach(scans, id: \.id) { scan in
                    let center = CLLocationCoordinate2D(
                        latitude: scan.segmentCenterLat ?? scan.latitude,
                        longitude: scan.segmentCenterLon ?? scan.longitude
                    )
                    let sideRaw = scan.segmentStreetSide ?? scan.spot?.streetSide
                    let status = ParkingSignalEvaluator.status(for: scan, now: now, leadMinutes: leadMinutes)
                    if let dir = scan.segmentDirection ?? scan.heading {
                        if sideRaw == nil || sideRaw!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sideRaw!.lowercased() == "unknown" {
                            let leftPts = CurbGeometry.curbAlignedPolyline(center: center, directionDegrees: dir, sideRaw: "left", lengthMeters: 20.0, offsetMeters: 4.5)
                            MapPolyline(coordinates: leftPts)
                                .stroke(
                                    status.color.opacity(0.28),
                                    style: StrokeStyle(
                                        lineWidth: 26,
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )
                            MapPolyline(coordinates: leftPts)
                                .stroke(
                                    status.color,
                                    style: StrokeStyle(
                                        lineWidth: 12,
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )
                            let rightPts = CurbGeometry.curbAlignedPolyline(center: center, directionDegrees: dir, sideRaw: "right", lengthMeters: 20.0, offsetMeters: 4.5)
                            MapPolyline(coordinates: rightPts)
                                .stroke(
                                    status.color.opacity(0.28),
                                    style: StrokeStyle(
                                        lineWidth: 26,
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )
                            MapPolyline(coordinates: rightPts)
                                .stroke(
                                    status.color,
                                    style: StrokeStyle(
                                        lineWidth: 12,
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )
                        } else {
                            let pts = CurbGeometry.curbAlignedPolyline(
                                center: center,
                                directionDegrees: dir,
                                sideRaw: sideRaw,
                                lengthMeters: 20.0,
                                offsetMeters: 4.5
                            )
                            MapPolyline(coordinates: pts)
                                .stroke(
                                    status.color.opacity(0.28),
                                    style: StrokeStyle(
                                        lineWidth: 26,
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )
                            MapPolyline(coordinates: pts)
                                .stroke(
                                    status.color,
                                    style: StrokeStyle(
                                        lineWidth: 12,
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )
                        }
                    }
                    // Unique pin for the sign scan location (always shown)
                    let pinCoord = CLLocationCoordinate2D(latitude: scan.latitude, longitude: scan.longitude)
                    Annotation(scan.address ?? "Sign", coordinate: pinCoord) {
                        VStack(spacing: 2) {
                            ZStack {
                                Circle()
                                    .fill(status.color)
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                    .shadow(radius: 1)
                                Image(systemName: "text.viewfinder")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            Text(status.label)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(status.color.opacity(0.12))
                                .foregroundStyle(status.color)
                                .clipShape(Capsule())
                        }
                        .accessibilityLabel("Sign scan: \(scan.address ?? "Unknown")")
                        .onLongPressGesture {
                            isEditingSegments = true
                            editingScanID = scan.id
                        }
                    }
                    
                    if isEditingSegments && (editingScanID == nil || editingScanID == scan.id) {
                        // Center handle (draggable)
                        Annotation("Center Handle", coordinate: center) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .shadow(radius: 1)
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        // Convert from current center point + translation
                                        guard let start = proxy.convert(center, to: .local) else { return }
                                        let newPoint = CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height)
                                        guard let newCoord = proxy.convert(newPoint, from: .local) else { return }
                                        scan.segmentCenterLat = newCoord.latitude
                                        scan.segmentCenterLon = newCoord.longitude
                                    }
                                    .onEnded { _ in try? _modelContext.save() }
                                )
                                .onTapGesture { editingScanID = scan.id }
                        }

                        // End handles (draggable) for adjusting direction and length
                        if let dir = scan.segmentDirection ?? scan.heading {
                            let sideRaw = scan.segmentStreetSide ?? scan.spot?.streetSide
                            let halfLen = max(5.0, (scan.segmentRadius ?? 15.0))
                            let lengthMeters = halfLen * 2.0
                            let pts = CurbGeometry.curbAlignedPolyline(center: center, directionDegrees: dir, sideRaw: sideRaw, lengthMeters: lengthMeters, offsetMeters: 4.5)
                            // Handle at start
                            Annotation("Start Handle", coordinate: pts[0]) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                    .shadow(radius: 1)
                                    .gesture(DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            guard let startPt = proxy.convert(pts[0], to: .local) else { return }
                                            let newPoint = CGPoint(x: startPt.x + value.translation.width, y: startPt.y + value.translation.height)
                                            guard let newCoord = proxy.convert(newPoint, from: .local) else { return }
                                            // Update direction and half-length based on drag
                                            let newDir = SegmentUtils.bearingDegrees(from: center, to: newCoord)
                                            let dist = SegmentUtils.distanceMeters(center, newCoord)
                                            scan.segmentDirection = CurbGeometry.normalizedHeading(newDir)
                                            scan.segmentRadius = max(5.0, dist)
                                        }
                                        .onEnded { _ in try? _modelContext.save() }
                                    )
                            }
                            // Handle at end
                            Annotation("End Handle", coordinate: pts[1]) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                    .shadow(radius: 1)
                                    .gesture(DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            guard let startPt = proxy.convert(pts[1], to: .local) else { return }
                                            let newPoint = CGPoint(x: startPt.x + value.translation.width, y: startPt.y + value.translation.height)
                                            guard let newCoord = proxy.convert(newPoint, from: .local) else { return }
                                            let newDir = SegmentUtils.bearingDegrees(from: center, to: newCoord)
                                            let dist = SegmentUtils.distanceMeters(center, newCoord)
                                            scan.segmentDirection = CurbGeometry.normalizedHeading(newDir)
                                            scan.segmentRadius = max(5.0, dist)
                                        }
                                        .onEnded { _ in try? _modelContext.save() }
                                    )
                            }
                        }

                        // Raw sign pin handle (draggable)
                        Annotation("Sign Pin Handle", coordinate: CLLocationCoordinate2D(latitude: scan.latitude, longitude: scan.longitude)) {
                            Rectangle()
                                .fill(Color.purple)
                                .frame(width: 14, height: 14)
                                .rotationEffect(.degrees(45))
                                .overlay(Rectangle().stroke(Color.white, lineWidth: 2).rotationEffect(.degrees(45)))
                                .shadow(radius: 1)
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard let startPt = proxy.convert(CLLocationCoordinate2D(latitude: scan.latitude, longitude: scan.longitude), to: .local) else { return }
                                        let newPoint = CGPoint(x: startPt.x + value.translation.width, y: startPt.y + value.translation.height)
                                        guard let newCoord = proxy.convert(newPoint, from: .local) else { return }
                                        scan.latitude = newCoord.latitude
                                        scan.longitude = newCoord.longitude
                                    }
                                    .onEnded { _ in try? _modelContext.save() }
                                )
                                .onTapGesture { editingScanID = scan.id }
                        }
                    }
                }
                
                // Active parked car pins (customizable per car)
                ForEach(sessions.filter { $0.endedAt == nil && $0.car != nil && $0.spot != nil }, id: \.id) { sess in
                    if let spot = sess.spot, let car = sess.car {
                        let coord = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
                        Annotation(car.nickname, coordinate: coord) {
                            ZStack {
                                // Car color background (if provided) else accent
                                Circle()
                                    .fill(carColor(for: car))
                                    .frame(width: 20, height: 20)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                    .shadow(radius: 1)
                                Image(systemName: car.iconName)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .accessibilityLabel("\(car.nickname) parked at \(spot.location)")
                        }
                    }
                }
                
                // Saved spots (tappable)
                ForEach(spots, id: \.id) { spot in
                    Annotation(spot.location,
                               coordinate: CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)) {
                        Button {
                            onSelectSpot(spot)
                        } label: {
                            Image(systemName: symbolName(for: spot))
                                .font(.title2)
                                .foregroundStyle(signalColor(for: spot))
                                .shadow(color: .white.opacity(0.85), radius: 1)
                                .shadow(radius: 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(spot.location)")
                    }
                }

                // Temporary pin (if any) — avoid if-let in MapContentBuilder
                if tempPin != nil {
                    Marker("New Spot", coordinate: tempPin!)
                        .tint(.purple)
                }

                // System user location dot (if permission is granted)
                UserAnnotation()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                guard showCityZoneOverlay else { return }
                let region = context.region
                debouncedLoadCityOverlays(center: region.center)
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in now = Date() }
            .task(id: showCityZoneOverlay) {
                if showCityZoneOverlay, let c = userCoordinate {
                    await loadCityOverlays(center: c)
                }
            }
            .overlay(alignment: .topTrailing) {
                VStack(spacing: 8) {
                    MapUserLocationButton()
                    MapCompass()
                    
                    Button(action: {
                        if isEditingSegments {
                            isEditingSegments = false
                            editingScanID = nil
                        } else {
                            isEditingSegments = true
                        }
                    }) {
                        Image(systemName: isEditingSegments ? "checkmark.circle" : "pencil.and.outline")
                            .font(.title3)
                            .foregroundColor(.primary)
                            .padding(8)
                            .background(.thinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(8)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 1)
                .padding()
            }
            .overlay(alignment: .topLeading) {
                if showLegend {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) { ColorSwatch(hex: "4CD964"); Text("Safe to Park").font(.caption) }
                        HStack(spacing: 6) { ColorSwatch(hex: "FF3B30"); Text("Illegal Now").font(.caption) }
                        HStack(spacing: 6) { ColorSwatch(hex: "FFCC00"); Text("Restriction Soon").font(.caption) }
                        HStack(spacing: 6) { ColorSwatch(hex: "007AFF"); Text("Permit/ADA").font(.caption) }
                        HStack(spacing: 6) { ColorSwatch(hex: "AF52DE"); Text("Metered/Paid").font(.caption) }
                        HStack(spacing: 6) { ColorSwatch(hex: "8E8E93"); Text("Unknown").font(.caption) }
                    }
                    .padding(8)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.1), lineWidth: 0.5))
                    .shadow(radius: 1)
                    .padding()
                }
            }
            .onAppear {
                // If we already have a user location, center on it on first appear
                if let c = userCoordinate {
                    center(on: c, span: 0.01)
                }
            }
            // Recenter when the user coordinate changes
            .onChange(of: MapCoordinateProxy(userCoordinate)) { coord in
                guard let lat = coord.latitude, let lon = coord.longitude else { return }
                center(on: CLLocationCoordinate2D(latitude: lat, longitude: lon), span: 0.01)
            }
            // Double-tap to add a pin at the tapped location
            .highPriorityGesture(
                SpatialTapGesture(count: 2)
                    .onEnded { value in
                        let point = value.location
                        if let coord = proxy.convert(point, from: .local) {
                            onAddPinAtCoordinate(coord)
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        }
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture(count: 1)
                    .onEnded { value in
                        let point = value.location
                        if let coord = proxy.convert(point, from: .local) {
                            if let hit = nearestScan(to: coord) { selectedScan = hit }
                        }
                    }
            )
            .sheet(item: $selectedScan) { scan in
                SignScanEditView(scan: scan)
                    .environment(\.modelContext, _modelContext)
            }
        }
    }

    private func loadCityOverlays(center: CLLocationCoordinate2D) async {
        let items = await ParkingDataProvider.shared.overlaysNear(center)
        await MainActor.run { self.cityOverlays = items }
    }

    @State private var lastOverlayLoad: Date? = nil
    private func debouncedLoadCityOverlays(center: CLLocationCoordinate2D) {
        let now = Date()
        if let last = lastOverlayLoad, now.timeIntervalSince(last) < 1.0 { return }
        lastOverlayLoad = now
        Task { await loadCityOverlays(center: center) }
    }

    private func center(on coordinate: CLLocationCoordinate2D, span: CLLocationDegrees) {
        withAnimation(.easeInOut) {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
                )
            )
        }
    }
    
    private func symbolName(for spot: ParkingSpot) -> String {
        return "mappin.circle.fill"
    }
    
    private enum SpotStatus { case parked, notAllowed, soon, normal }

    private func spotStatus(for spot: ParkingSpot) -> SpotStatus {
        if spot.parkSessions.contains(where: { $0.endedAt == nil }) { return .parked }
        if spot.isRestrictedNow(at: now) { return .notAllowed }
        if let next = spot.nextRestrictionDate(from: now), next.timeIntervalSinceNow <= 2 * 60 * 60 { return .soon }
        return .normal
    }

    private func overlayColor(for status: SpotStatus) -> Color {
        switch status {
        case .parked: return .green
        case .notAllowed: return .red
        case .soon: return .orange
        case .normal: return .teal
        }
    }

    private func signalColor(for spot: ParkingSpot) -> Color {
        let status = ParkingSignalEvaluator.status(for: spot, now: now, leadMinutes: leadMinutes)
        return status.color
    }

    private func signalColor(for scan: SignScan) -> Color {
        let status = ParkingSignalEvaluator.status(for: scan, now: now, leadMinutes: leadMinutes)
        return status.color
    }
}

private struct MapCoordinateProxy: Equatable {
    let latitude: CLLocationDegrees?
    let longitude: CLLocationDegrees?

    init(_ coordinate: CLLocationCoordinate2D?) {
        self.latitude = coordinate?.latitude
        self.longitude = coordinate?.longitude
    }
}

private struct ColorSwatch: View {
    let hex: String
    var body: some View {
        Circle()
            .fill(Color(uiColor: UIColor(hex: hex)).opacity(0.9))
            .frame(width: 14, height: 14)
    }
}

private extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        Scanner(string: s).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch s.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

private extension MapView {
    func ribbonColor(for scan: SignScan) -> Color {
        let status = ParkingSignalEvaluator.status(for: scan, now: now, leadMinutes: leadMinutes)
        switch status {
        case .green: return Color(uiColor: UIColor(hex: "4CD964"))
        case .red: return Color(uiColor: UIColor(hex: "FF3B30"))
        case .yellow: return Color(uiColor: UIColor(hex: "FFCC00"))
        case .blue: return Color(uiColor: UIColor(hex: "007AFF"))
        case .purple: return Color(uiColor: UIColor(hex: "AF52DE"))
        case .gray: return Color(uiColor: UIColor(hex: "8E8E93"))
        }
    }

    func nearestScan(to coord: CLLocationCoordinate2D) -> SignScan? {
        guard !scans.isEmpty else { return nil }
        var best: (SignScan, Double)? = nil
        for s in scans {
            let center = CLLocationCoordinate2D(latitude: s.segmentCenterLat ?? s.latitude, longitude: s.segmentCenterLon ?? s.longitude)
            let dir = s.segmentDirection ?? s.heading
            let side = s.segmentStreetSide ?? s.spot?.streetSide
            if let dir {
                let pts = CurbGeometry.curbAlignedPolyline(center: center, directionDegrees: dir, sideRaw: side, lengthMeters: 20.0, offsetMeters: 4.5)
                let cand = [pts[0], CLLocationCoordinate2D(latitude: (pts[0].latitude + pts[1].latitude)/2, longitude: (pts[0].longitude + pts[1].longitude)/2), pts[1]]
                let d = cand.map { SegmentUtils.distanceMeters($0, coord) }.min() ?? .greatestFiniteMagnitude
                if best == nil || d < best!.1 { best = (s, d) }
            } else {
                let d = SegmentUtils.distanceMeters(center, coord)
                if best == nil || d < best!.1 { best = (s, d) }
            }
        }
        if let (s, d) = best, d <= 15 { return s }
        return nil
    }
    
    func carColor(for car: Car) -> Color {
        if let hex = car.colorHex, !hex.isEmpty {
            return Color(uiColor: UIColor(hex: hex))
        }
        return .accentColor
    }
}

