import SwiftUI
import SwiftData

/// Parking state for one spot screen. It lives on the parent view so the car-picker sheet
/// and schedule prompt can stay attached there rather than to List rows, which unload on scroll.
@Observable
final class SpotParkingModel {
    var selectedCarID: UUID?
    var pendingAlerts: [UUID: Date] = [:] // carID -> next move-alert fire date
    var showCarPicker = false
    var showSchedulePrompt = false
    var promptCar: Car?
    var nextRestrictionForPrompt: Date?

    /// Park `car` here; without auto-scheduling, offer to schedule its move alert.
    func park(_ car: Car, at spot: ParkingSpot, context: ModelContext) {
        Task {
            await ParkingSessionService(context: context).park(car, at: spot)
            if !UserDefaults.standard.bool(forKey: ParkingSessionService.autoScheduleKey) {
                promptCar = car
                nextRestrictionForPrompt = spot.nextRestrictionDate()
                showSchedulePrompt = true
            }
            refresh(for: spot)
        }
    }

    func endParking(for carID: UUID, cars: [Car], at spot: ParkingSpot, context: ModelContext) {
        guard let car = cars.first(where: { $0.id == carID }) else { return }
        Task {
            await ParkingSessionService(context: context).end(car, at: spot)
            refresh(for: spot)
        }
    }

    func endAll(at spot: ParkingSpot, context: ModelContext) {
        Task {
            await ParkingSessionService(context: context).endAll(at: spot)
            refresh(for: spot)
        }
    }

    func scheduleMoveAlert(for car: Car, at spot: ParkingSpot, context: ModelContext) {
        Task {
            await ParkingSessionService(context: context).scheduleMoveAlert(for: car, at: spot)
            refresh(for: spot)
        }
    }

    func cancelMoveAlert(for car: Car, at spot: ParkingSpot, context: ModelContext) {
        Task {
            await ParkingSessionService(context: context).cancelMoveAlert(forCarID: car.id)
            refresh(for: spot)
        }
    }

    func refresh(for spot: ParkingSpot) {
        let carIDs = spot.parkSessions.filter { $0.endedAt == nil }.compactMap { $0.car?.id }
        Task {
            pendingAlerts = await ParkingSessionService.pendingMoveAlertDates(forCarIDs: carIDs)
        }
    }
}

/// The Parking, Upcoming and Assign Car sections of the spot screen.
struct SpotParkingSections: View {
    @Environment(\.modelContext) private var context
    @Bindable var spot: ParkingSpot
    let model: SpotParkingModel
    @Query private var cars: [Car]

    var body: some View {
        parkingSection()
        upcomingSection()
        assignCarSection()
    }

    private var activeCar: Car? {
        spot.parkSessions.first(where: { $0.endedAt == nil && $0.car != nil })?.car
    }

    private var carSelectionBinding: Binding<UUID?> {
        Binding<UUID?>(
            get: { model.selectedCarID },
            set: { newID in
                model.selectedCarID = newID
                if let newID, let car = cars.first(where: { $0.id == newID }) {
                    model.park(car, at: spot, context: context)
                }
            }
        )
    }

    @ViewBuilder
    private func parkingSection() -> some View {
        Section(header: Text("Parking")) {
            if let car = activeCar {
                HStack(spacing: 8) {
                    Image(systemName: car.iconName)
                        .foregroundStyle(.tint)
                    Text("\(car.nickname) is parked here")
                        .foregroundStyle(.green)
                }
            }
            if spot.isCurrentlyParked {
                HStack(spacing: 8) {
                    Image(systemName: "parkingsign.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .green)
                    Text("You're parked here")
                        .foregroundStyle(.green)
                }
                Button(role: .destructive) {
                    model.endAll(at: spot, context: context)
                } label: {
                    Label("End Parking", systemImage: "xmark.circle")
                }
            } else {
                Text("Not parked here")
                    .foregroundColor(.secondary)
                Button {
                    model.showCarPicker = true
                } label: {
                    Label("Park Here", systemImage: "parkingsign")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    @ViewBuilder
    private func upcomingSection() -> some View {
        Section(header: Text("Upcoming")) {
            // Upcoming restrictions for this spot (next 3)
            let items = upcomingRestrictions(limit: 3)
            if items.isEmpty {
                Text("No upcoming restrictions found.").foregroundColor(.secondary)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, entry in
                    let r = entry.0
                    let date = entry.1
                    HStack {
                        Image(systemName: "calendar")
                        VStack(alignment: .leading) {
                            Text(r.type.displayName)
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
            }

            // Scheduled alerts for currently parked cars at this spot
            let activeCarSessions = spot.parkSessions.filter { $0.endedAt == nil && $0.car != nil }
            if activeCarSessions.isEmpty {
                Text("No cars parked here.").foregroundColor(.secondary)
            } else {
                ForEach(activeCarSessions, id: \.id) { sess in
                    if let car = sess.car {
                        let fire = model.pendingAlerts[car.id]
                        HStack {
                            Image(systemName: car.iconName).foregroundStyle(.tint)
                            VStack(alignment: .leading) {
                                Text(car.nickname)
                                if let fire { Text("Alert: \(fire.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundColor(.secondary) }
                                else { Text("No alert scheduled").font(.caption).foregroundColor(.secondary) }
                            }
                            Spacer()
                            if fire == nil {
                                Button("Schedule") { model.scheduleMoveAlert(for: car, at: spot, context: context) }
                                    .buttonStyle(.bordered)
                            } else {
                                Button("Cancel") { model.cancelMoveAlert(for: car, at: spot, context: context) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func assignCarSection() -> some View {
        Section("Assign Car to This Spot") {
            Picker("Car", selection: carSelectionBinding) {
                Text("None").tag(Optional<UUID>.none)
                ForEach(cars, id: \.id) { car in
                    Text(car.nickname).tag(Optional(car.id))
                }
            }
            if let selID = model.selectedCarID {
                if let active = activeSession(for: selID) {
                    Button(role: .destructive) {
                        model.endParking(for: selID, cars: cars, at: spot, context: context)
                    } label: {
                        Label("End Parking for \(active.car?.nickname ?? "Car")", systemImage: "xmark.circle")
                    }
                }
            }
        }
    }

    private func upcomingRestrictions(limit: Int = 3, from now: Date = Date()) -> [(Restriction, Date)] {
        let cal = Calendar.current
        var results: [(Restriction, Date)] = []
        for r in spot.restrictions {
            // Skip if days not set; we can't predict windows
            let days = r.daysOfWeek
            if days.isEmpty { continue }
            // For the next 14 days, collect starts
            for offset in 0...13 {
                guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
                let w = (cal.component(.weekday, from: day) + 6) % 7
                guard days.contains(w) else { continue }
                let sh = cal.component(.hour, from: r.startTime)
                let sm = cal.component(.minute, from: r.startTime)
                var comps = cal.dateComponents([.year, .month, .day], from: day)
                comps.hour = sh; comps.minute = sm; comps.second = 0
                if let start = cal.date(from: comps), start > now {
                    results.append((r, start))
                }
            }
        }
        results.sort { $0.1 < $1.1 }
        if results.count > limit { return Array(results.prefix(limit)) }
        return results
    }

    private func activeSession(for carID: UUID) -> ParkSession? {
        spot.parkSessions.first(where: { session in
            session.endedAt == nil && session.car?.id == carID
        })
    }
}
