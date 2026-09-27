import Foundation
import SwiftData
import UserNotifications

/// Notification/alarm side effects of parking, behind a protocol so tests can observe them.
protocol ParkingAlerts {
    func scheduleSpotReminders(for spot: ParkingSpot) async
    func cancelSpotReminders(for spot: ParkingSpot) async
    func scheduleMoveAlert(for car: Car, at spot: ParkingSpot) async
    func cancelMoveAlerts(forCarID carID: UUID) async
}

/// The single place that starts and ends parking sessions and keeps their alerts in sync.
///
/// Rules:
/// - A car has at most one open session; a car-less ("just me") session is likewise unique.
///   Parking one car never touches another car's session.
/// - A spot's weekly restriction reminders exist while anyone is parked there and are
///   cancelled once the last open session at that spot ends.
/// - A car's "move your car" alert (and its AlarmKit countdown) is cancelled whenever that
///   car's session ends or moves.
struct ParkingSessionService {
    /// `@AppStorage` key for "schedule the move-your-car alert automatically when parking".
    static let autoScheduleKey = "autoScheduleAlertOnPark"

    let context: ModelContext
    var alerts: ParkingAlerts = SystemParkingAlerts()

    static func moveAlertPrefix(carID: UUID) -> String {
        "nextRestriction.car.\(carID.uuidString).spot."
    }

    static func moveAlertID(carID: UUID, spotID: UUID) -> String {
        moveAlertPrefix(carID: carID) + spotID.uuidString
    }

    /// Park `car` (or a car-less session when nil) at `spot`, replacing its previous session.
    /// - Parameter scheduleMoveAlert: nil follows the user's auto-schedule setting.
    @discardableResult
    func park(_ car: Car?, at spot: ParkingSpot, scheduleMoveAlert: Bool? = nil, now: Date = Date()) async -> ParkSession {
        let replaced = openSessions().filter { belongs($0, to: car) }
        for s in replaced { s.endedAt = now }

        let session = ParkSession(spot: spot, startedAt: now, endedAt: nil, car: car)
        context.insert(session)
        if !spot.parkSessions.contains(where: { $0.id == session.id }) { spot.parkSessions.append(session) }
        if let car, !car.sessions.contains(where: { $0.id == session.id }) { car.sessions.append(session) }
        try? context.save()

        await cleanUpAlerts(after: replaced, keepingSpotID: spot.id)
        await alerts.scheduleSpotReminders(for: spot)
        let wantsMoveAlert = scheduleMoveAlert ?? UserDefaults.standard.bool(forKey: Self.autoScheduleKey)
        if let car, wantsMoveAlert {
            await alerts.scheduleMoveAlert(for: car, at: spot)
        }
        return session
    }

    /// End `car`'s open session (car-less sessions when nil), optionally only at `spot`.
    func end(_ car: Car?, at spot: ParkingSpot? = nil, now: Date = Date()) async {
        let targets = openSessions().filter { s in
            belongs(s, to: car) && (spot == nil || s.spot?.id == spot?.id)
        }
        await finish(targets, now: now)
    }

    /// End every open session at `spot`, whoever it belongs to.
    func endAll(at spot: ParkingSpot, now: Date = Date()) async {
        await finish(openSessions().filter { $0.spot?.id == spot.id }, now: now)
    }

    func scheduleMoveAlert(for car: Car, at spot: ParkingSpot) async {
        await alerts.scheduleMoveAlert(for: car, at: spot)
    }

    func cancelMoveAlert(forCarID carID: UUID) async {
        await alerts.cancelMoveAlerts(forCarID: carID)
    }

    /// Next fire date of each car's pending "move your car" notification.
    static func pendingMoveAlertDates(forCarIDs carIDs: [UUID]) async -> [UUID: Date] {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        var result: [UUID: Date] = [:]
        for carID in carIDs {
            let prefix = moveAlertPrefix(carID: carID)
            let dates = pending
                .filter { $0.identifier.hasPrefix(prefix) }
                .compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
            if let first = dates.min() { result[carID] = first }
        }
        return result
    }

    // MARK: - Private

    private func openSessions() -> [ParkSession] {
        let descriptor = FetchDescriptor<ParkSession>(predicate: #Predicate { $0.endedAt == nil })
        return (try? context.fetch(descriptor)) ?? []
    }

    private func belongs(_ session: ParkSession, to car: Car?) -> Bool {
        if let car { return session.car?.id == car.id }
        return session.car == nil
    }

    private func finish(_ sessions: [ParkSession], now: Date) async {
        guard !sessions.isEmpty else { return }
        for s in sessions { s.endedAt = now }
        try? context.save()
        await cleanUpAlerts(after: sessions, keepingSpotID: nil)
    }

    private func cleanUpAlerts(after ended: [ParkSession], keepingSpotID: UUID?) async {
        var carIDs = Set<UUID>()
        var spots: [UUID: ParkingSpot] = [:]
        for s in ended {
            if let id = s.car?.id { carIDs.insert(id) }
            if let spot = s.spot { spots[spot.id] = spot }
        }
        for id in carIDs {
            await alerts.cancelMoveAlerts(forCarID: id)
        }
        let stillOccupied = Set(openSessions().compactMap { $0.spot?.id })
        for (id, spot) in spots where id != keepingSpotID && !stillOccupied.contains(id) {
            await alerts.cancelSpotReminders(for: spot)
        }
    }
}

/// Live implementation backed by `NotificationManager`, `UNUserNotificationCenter` and `AlarmService`.
struct SystemParkingAlerts: ParkingAlerts {
    func scheduleSpotReminders(for spot: ParkingSpot) async {
        await NotificationManager.shared.schedule(for: spot.restrictions, spot: spot)
    }

    func cancelSpotReminders(for spot: ParkingSpot) async {
        await NotificationManager.shared.cancel(for: spot.restrictions, spot: spot)
    }

    func scheduleMoveAlert(for car: Car, at spot: ParkingSpot) async {
        guard let start = spot.nextRestrictionDate() else { return }
        // Replace, don't stack: drop this car's previous alert and countdown first.
        await cancelMoveAlerts(forCarID: car.id)

        let lead = TimeInterval(max(0, NotificationManager.shared.leadMinutes) * 60)
        let fireDate = max(start.addingTimeInterval(-lead), Date().addingTimeInterval(2))

        if await NotificationManager.shared.requestAuthorizationIfNeeded() {
            let content = UNMutableNotificationContent()
            content.title = "Move your \(car.nickname)"
            content.body = "Restriction at \(spot.location) starts soon."
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: ParkingSessionService.moveAlertID(carID: car.id, spotID: spot.id),
                content: content,
                trigger: trigger
            )
            try? await UNUserNotificationCenter.current().add(request)
        }

        let seconds = fireDate.timeIntervalSinceNow
        if seconds > 1 {
            _ = await AlarmService.shared.requestAuthorization()
            _ = try? await AlarmService.shared.scheduleCountdown(
                seconds: seconds,
                title: LocalizedStringResource("Restriction Starts"),
                carID: car.id,
                spotID: spot.id
            )
        }
    }

    func cancelMoveAlerts(forCarID carID: UUID) async {
        let center = UNUserNotificationCenter.current()
        let prefix = ParkingSessionService.moveAlertPrefix(carID: carID)
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        await AlarmService.shared.cancelAlarms(forCarID: carID)
    }
}
