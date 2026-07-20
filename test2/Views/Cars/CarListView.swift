// CarListView
// - Uses centralized session management via Car+Parking (toggle/assign/start/end).
// - Uses NotificationManager for scheduling/canceling restriction alerts.
// - Avoids duplicating nextRestrictionDate logic; prefer ParkingSpot+Status helpers.

import SwiftUI
import SwiftData
import CoreLocation
import UserNotifications
import Combine

struct CarListView: View {
    @Environment(\.modelContext) private var context
    @Query private var cars: [Car]
    @Query private var spots: [ParkingSpot]
    @Query private var sessions: [ParkSession]

    @State private var showAdd = false
    @State private var nickname = ""
    @State private var licensePlate = ""
    @State private var colorHex = ""
    @State private var iconName = "car.fill"
    @State private var showParkPicker = false
    @State private var carToAssign: Car? = nil
    @StateObject private var locationManager = LocationManager()
    @State private var now = Date()
    @AppStorage("alertLeadMinutes") private var leadMinutes: Int = 15
    @State private var detailSpot: ParkingSpot? = nil
    @State private var lastUsedCarID: UUID? = nil
    private static let lastUsedCarKey = "CarList.LastUsedCarID"

    @State private var newSpotOrientation: String = "with"

    var body: some View {
        NavigationStack {
            List {
                let lastUsed = cars.first(where: { $0.id == lastUsedCarID })
                if let last = lastUsed, last.sessions.first(where: { $0.endedAt == nil }) == nil {
                    Section("Last Used") {
                        HStack(spacing: 12) {
                            Image(systemName: last.iconName)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading) {
                                Text(last.nickname)
                                    .font(.headline)
                                if let plate = last.licensePlate, !plate.isEmpty {
                                    Text(plate)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if locationManager.lastLocation != nil {
                                Button {
                                    if let nearest = nearestSpot() {
                                        assign(last, to: nearest)
                                    } else {
                                        carToAssign = last
                                        showParkPicker = true
                                    }
                                } label: {
                                    Label("Quick Park", systemImage: "location.circle")
                                }
                                .buttonStyle(.bordered)
                            }
                            if locationManager.lastLocation != nil {
                                Button {
                                    parkHere(last)
                                } label: {
                                    Label("Park Here", systemImage: "mappin.and.ellipse")
                                }
                                .buttonStyle(.bordered)
                            }
                            Button {
                                carToAssign = last
                                showParkPicker = true
                            } label: {
                                Label("Park at Spot", systemImage: "parkingsign")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                let parkedCars = cars.filter { $0.sessions.contains { $0.endedAt == nil } }
                if !parkedCars.isEmpty {
                    Section("Currently Parked") {
                        ForEach(parkedCars, id: \.id) { car in
                            if let activeSession = car.sessions.first(where: { $0.endedAt == nil }), let activeSpot = activeSession.spot {
                                HStack(spacing: 8) {
                                    Image(systemName: car.iconName)
                                        .foregroundStyle(.tint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(car.nickname)
                                            .font(.subheadline)
                                        HStack(spacing: 6) {
                                            Image(systemName: "parkingsign.circle.fill")
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, .green)
                                            Text(activeSpot.location)
                                                .font(.caption)
                                                .foregroundColor(.green)
                                                .lineLimit(1)
                                            Text("• \(elapsedString(since: activeSession.startedAt))")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                            if let next = nextRestrictionDate(for: activeSpot) {
                                                Text("• next: \(countdownString(to: next))")
                                                    .font(.caption)
                                                    .foregroundColor(.green)
                                            }
                                            Button {
                                                detailSpot = activeSpot
                                            } label: {
                                                Image(systemName: "info.circle")
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        let status = ParkingSignalEvaluator.status(for: activeSpot, now: now, leadMinutes: leadMinutes)
                                        HStack(spacing: 6) {
                                            Circle().fill(status.color).frame(width: 8, height: 8)
                                            Text(status.label).font(.caption).foregroundColor(status.color)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if cars.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No cars yet")
                            .font(.headline)
                        Text("Add your car to track parking sessions and alarms.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                ForEach(cars, id: \.id) { car in
                    HStack(spacing: 12) {
                        Image(systemName: car.iconName)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(car.nickname)
                                .font(.headline)
                            if let plate = car.licensePlate, !plate.isEmpty {
                                Text(plate)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if let activeSession = car.sessions.first(where: { $0.endedAt == nil }), let activeSpot = activeSession.spot {
                            HStack(spacing: 6) {
                                Image(systemName: "parkingsign.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .green)
                                Text(activeSpot.location)
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .lineLimit(1)
                                Text("• \(elapsedString(since: activeSession.startedAt))")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                if let next = nextRestrictionDate(for: activeSpot) {
                                    Text("• next: \(countdownString(to: next))")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                                let status = ParkingSignalEvaluator.status(for: activeSpot, now: now, leadMinutes: leadMinutes)
                                Text("•")
                                Circle().fill(status.color).frame(width: 8, height: 8)
                                Text(status.label).font(.caption).foregroundColor(status.color)
                                Button {
                                    detailSpot = activeSpot
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.15))
                            .clipShape(Capsule())
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if let _ = car.sessions.first(where: { $0.endedAt == nil }) {
                            Button {
                                carToAssign = car
                                showParkPicker = true
                            } label: {
                                Label("Move to Spot", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .tint(.green)
                            Button(role: .destructive) {
                                endParking(for: car)
                            } label: {
                                Label("End Parking", systemImage: "xmark.circle")
                            }
                        } else {
                            if locationManager.lastLocation != nil {
                                Button {
                                    parkHere(car)
                                } label: {
                                    Label("Park Here (New Spot)", systemImage: "mappin.and.ellipse")
                                }
                                .tint(.orange)
                            }
                            if locationManager.lastLocation != nil {
                                Button {
                                    if let nearest = nearestSpot() {
                                        assign(car, to: nearest)
                                    } else {
                                        carToAssign = car
                                        showParkPicker = true
                                    }
                                } label: {
                                    Label("Quick Park (Nearest)", systemImage: "location.circle")
                                }
                                .tint(.blue)
                            }
                            Button {
                                carToAssign = car
                                showParkPicker = true
                            } label: {
                                Label("Park at Spot", systemImage: "parkingsign")
                            }
                            .tint(.green)
                        }
                    }
                    .contextMenu {
                        if let _ = car.sessions.first(where: { $0.endedAt == nil }) {
                            Button {
                                carToAssign = car
                                showParkPicker = true
                            } label: {
                                Label("Move to Spot", systemImage: "arrow.triangle.2.circlepath")
                            }
                            Button(role: .destructive) {
                                endParking(for: car)
                            } label: {
                                Label("End Parking", systemImage: "xmark.circle")
                            }
                        } else {
                            Button {
                                carToAssign = car
                                showParkPicker = true
                            } label: {
                                Label("Park at Spot", systemImage: "parkingsign")
                            }
                        }
                    }
                }
                .onDelete(perform: deleteCars)
            }
            .navigationTitle("Cars")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAdd = true
                    } label: {
                        Label("Add Car", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    Form {
                        Section("Details") {
                            TextField("Nickname", text: $nickname)
                            TextField("License Plate (optional)", text: $licensePlate)
                            TextField("Color Hex (optional)", text: $colorHex)
                            TextField("SF Symbol (optional)", text: $iconName)
                                .textInputAutocapitalization(.never)
                        }
                    }
                    .navigationTitle("New Car")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { resetForm(); showAdd = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { addCar() }
                                .disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .sheet(isPresented: $showParkPicker) {
                NavigationStack {
                    List {
                        if spots.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No saved spots yet")
                                    .font(.headline)
                                Text("Add a spot from the Dashboard, then assign your car to it here.")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            ForEach(sortedSpots(), id: \.id) { spot in
                                Button {
                                    if let car = carToAssign {
                                        assign(car, to: spot)
                                        showParkPicker = false
                                        carToAssign = nil
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "mappin.and.ellipse")
                                            .foregroundStyle(.tint)
                                        VStack(alignment: .leading) {
                                            Text(spot.location)
                                                .font(.headline)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Assign Spot")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showParkPicker = false
                                carToAssign = nil
                            }
                        }
                        ToolbarItemGroup(placement: .confirmationAction) {
                            if carToAssign != nil {
                                Button("Nearest") {
                                    if let car = carToAssign, let spot = nearestSpot() {
                                        assign(car, to: spot)
                                        showParkPicker = false
                                        carToAssign = nil
                                    }
                                }
                                Button("Recent") {
                                    if let car = carToAssign, let spot = mostRecentSpot() {
                                        assign(car, to: spot)
                                        showParkPicker = false
                                        carToAssign = nil
                                    }
                                }
                                if locationManager.lastLocation != nil {
                                    Button("Park Here") {
                                        if let car = carToAssign { parkHere(car); showParkPicker = false; carToAssign = nil }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .sheet(item: $detailSpot) { spot in
                NavigationStack {
                    ParkingSpotDetailView(spot: spot, onUpdate: { _ in })
                        .environment(\.modelContext, context)
                }
            }
            .onAppear {
                if let s = UserDefaults.standard.string(forKey: Self.lastUsedCarKey), let id = UUID(uuidString: s) {
                    lastUsedCarID = id
                }
                if locationManager.authorizationStatus == .notDetermined {
                    locationManager.requestWhenInUseAuthorization()
                } else if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                    locationManager.startUpdatingLocation()
                }
            }
            .onDisappear {
                locationManager.stopUpdatingLocation()
            }
            .onChange(of: locationManager.authorizationStatus) { newValue in
                if newValue == .authorizedWhenInUse || newValue == .authorizedAlways {
                    locationManager.startUpdatingLocation()
                }
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                now = Date()
            }
        }
    }

    private func addCar() {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNickname.isEmpty else { return }
        let car = Car(
            nickname: trimmedNickname,
            licensePlate: licensePlate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : licensePlate,
            colorHex: colorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : colorHex,
            iconName: iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "car.fill" : iconName
        )
        context.insert(car)
        try? context.save()
        resetForm()
        showAdd = false
    }

    private func resetForm() {
        nickname = ""
        licensePlate = ""
        colorHex = ""
        iconName = "car.fill"
    }

    private func deleteCars(at offsets: IndexSet) {
        let targets = offsets.map { cars[$0] }
        for car in targets {
            context.delete(car)
        }
        try? context.save()
    }

    private func assign(_ car: Car, to spot: ParkingSpot) {
        // End any existing active session and start a new one at the given spot using centralized API
        let now = Date()
        let _ = car.startParking(at: spot, now: now, in: context)
        try? context.save()

        // Remember last used car for quick actions
        saveLastUsed(car)

        // Schedule weekly notifications for this spot's restrictions (centralized policy)
        Task { await NotificationManager.shared.schedule(for: spot.restrictions, spot: spot) }
    }

    private func endParking(for car: Car) {
        car.endCurrentParking(at: Date())
        try? context.save()
        saveLastUsed(car)

        // Cancel any previously scheduled weekly notifications for the last spot of this car (best-effort)
        if let spot = car.activeSession?.spot { // if still active (shouldn't be), skip cancel
        } else {
            // We don't know the last spot directly; as a simple approach, cancel for all spots with active sessions ended now
            // (In a future refactor, track CurrentParking to know the last spot directly.)
            // For now, this is a no-op because schedule uses per-restriction identifiers; cancel will be called when moving/starting elsewhere.
        }
    }

    private func elapsedString(since date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        let minutes = seconds / 60
        let hours = minutes / 60
        if hours > 0 {
            let rem = minutes % 60
            return "\(hours)h\(rem > 0 ? " \(rem)m" : "")"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "Just now"
        }
    }

    private func sortedSpots() -> [ParkingSpot] {
        if let coord = locationManager.lastLocation?.coordinate {
            return spots.sorted { a, b in
                let da = distance(from: coord, to: a)
                let db = distance(from: coord, to: b)
                if abs(da - db) > 1 {
                    return da < db
                }
                // Tie-breaker: most recent usage
                return latestUsageDate(for: a) > latestUsageDate(for: b)
            }
        } else {
            return spots.sorted { latestUsageDate(for: $0) > latestUsageDate(for: $1) }
        }
    }

    private func nearestSpot() -> ParkingSpot? {
        guard let coord = locationManager.lastLocation?.coordinate else { return nil }
        return spots.min(by: { distance(from: coord, to: $0) < distance(from: coord, to: $1) })
    }

    private func mostRecentSpot() -> ParkingSpot? {
        return spots.max(by: { latestUsageDate(for: $0) < latestUsageDate(for: $1) })
    }

    private func latestUsageDate(for spot: ParkingSpot) -> Date {
        let sessionDate = spot.parkSessions.compactMap { $0.startedAt }.max() ?? .distantPast
        return sessionDate
    }

    private func distance(from coord: CLLocationCoordinate2D, to spot: ParkingSpot) -> CLLocationDistance {
        let a = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let b = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
        return a.distance(from: b)
    }

    private func nextRestrictionDate(for spot: ParkingSpot, from now: Date = Date()) -> Date? {
        return spot.nextRestrictionDate(from: now)
    }

    private func countdownString(to date: Date) -> String {
        let interval = max(0, Int(date.timeIntervalSinceNow))
        let minutes = interval / 60
        let hours = minutes / 60
        let days = hours / 24
        if days > 0 {
            let remH = hours % 24
            return "\(days)d\(remH > 0 ? " \(remH)h" : "")"
        } else if hours > 0 {
            let remM = minutes % 60
            return "\(hours)h\(remM > 0 ? " \(remM)m" : "")"
        } else if minutes > 0 {
            let secs = interval % 60
            return "\(minutes)m\(secs > 0 ? " \(secs)s" : "")"
        } else {
            return "now"
        }
    }

    private func scheduleNextRestrictionNotification(for car: Car, at spot: ParkingSpot) {
        guard let next = nextRestrictionDate(for: spot) else { return }
        let center = UNUserNotificationCenter.current()
        let id = "nextRestriction.car.\(car.id.uuidString).spot.\(spot.id.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let schedule: () -> Void = {
            let content = UNMutableNotificationContent()
            content.title = "Move your \(car.nickname)"
            content.body = "Restriction at \(spot.location) starts soon."
            content.sound = .default
            if #available(iOS 15.0, *) {
                content.interruptionLevel = .timeSensitive
            }
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: next)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            center.add(req, withCompletionHandler: nil)
        }

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                schedule()
            case .denied, .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted { schedule() }
                }
            @unknown default:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted { schedule() }
                }
            }
        }

        // Also attempt to schedule an AlarmKit countdown (if supported) with metadata
        let seconds = next.timeIntervalSinceNow
        if seconds > 1 {
            Task {
                _ = await AlarmService.shared.requestAuthorization()
                do {
                    let _ = try await AlarmService.shared.scheduleCountdown(seconds: seconds, title: LocalizedStringResource("Restriction Starts"), carID: car.id, spotID: spot.id)
                } catch { }
            }
        }
    }

    private func cancelNextRestrictionNotification(for car: Car) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextRestriction.car.\(car.id.uuidString)"])
    }

    private func saveLastUsed(_ car: Car) {
        lastUsedCarID = car.id
        UserDefaults.standard.set(car.id.uuidString, forKey: Self.lastUsedCarKey)
    }

    private func parkHere(_ car: Car) {
        guard let loc = locationManager.lastLocation else {
            carToAssign = car; showParkPicker = true; return
        }
        let coordinate = loc.coordinate
        reverseGeocode(coordinate: coordinate) { label in
            let locationLabel = label ?? String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
            let storedSide = DrivingSide.storedSide(from: newSpotOrientation)
            let newSpot = ParkingSpot(location: locationLabel, latitude: coordinate.latitude, longitude: coordinate.longitude, streetSide: storedSide, restrictions: [])
            context.insert(newSpot)
            do {
                try context.save()
                assign(car, to: newSpot)
            } catch {
                // Fallback: try assign even if save failed initially
                assign(car, to: newSpot)
            }
        }
    }

    private func reverseGeocode(coordinate: CLLocationCoordinate2D, completion: @escaping (String?) -> Void) {
        let geocoder = CLGeocoder()
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        geocoder.reverseGeocodeLocation(loc) { placemarks, _ in
            if let p = placemarks?.first {
                let parts = [p.name, p.thoroughfare, p.locality].compactMap { $0 }
                completion(parts.isEmpty ? nil : parts.joined(separator: ", "))
            } else {
                completion(nil)
            }
        }
    }
}

#Preview {
    CarListView()
        .modelContainer(for: [Car.self, ParkingSpot.self, ParkSession.self], inMemory: true)
}

