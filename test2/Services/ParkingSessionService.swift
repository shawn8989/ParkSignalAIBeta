import Foundation
import SwiftData
import UserNotifications

/// Notification/alarm side effects of parking, behind a protocol so tests can observe them.
@MainActor
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
    var alerts: any ParkingAlerts
    init(context: ModelContext, alerts: (any ParkingAlerts)? = nil) {
        self.context = context
        self.alerts = alerts ?? SystemParkingAlerts(context: context)
    }

    static func moveAlertPrefix(carID: UUID) -> String {
        "nextRestriction.car.\(carID.uuidString).spot."
    }

    static func moveAlertID(carID: UUID, spotID: UUID) -> String {
        moveAlertPrefix(carID: carID) + spotID.uuidString
    }

    /// Park `car` (or a car-less session when nil) at `spot`, replacing its previous session.
    /// - Parameter scheduleMoveAlert: nil follows the user's auto-schedule setting.
    @discardableResult
    func park(_ car: Car?, at spot: ParkingSpot, scheduleMoveAlert: Bool? = nil, now: Date = Date()) async -> Bool {
        let replaced: [ParkSession]
        do { replaced = try openSessions().filter { belongs($0, to: car) } }
        catch { AppIssueStore.shared.message = "Couldn’t read parking sessions: \(error.localizedDescription)"; return false }
        for s in replaced { s.endedAt = now }

        let session = ParkSession(spot: spot, startedAt: now, endedAt: nil, car: car)
        context.insert(session)
        if !spot.parkSessionsList.contains(where: { $0.id == session.id }) { spot.parkSessionsList.append(session) }
        if let car, !car.sessionsList.contains(where: { $0.id == session.id }) { car.sessionsList.append(session) }
        do { try context.save() } catch {
            context.rollback()
            AppIssueStore.shared.message = "Couldn't save parking: \(error.localizedDescription)"
            return false
        }

        await cleanUpAlerts(after: replaced, keepingSpotID: spot.id)
        await alerts.scheduleSpotReminders(for: spot)
        let wantsMoveAlert = scheduleMoveAlert ?? UserDefaults.standard.bool(forKey: Self.autoScheduleKey)
        if let car, wantsMoveAlert {
            await alerts.scheduleMoveAlert(for: car, at: spot)
        }
        return true
    }

    /// End `car`'s open session (car-less sessions when nil), optionally only at `spot`.
    func end(_ car: Car?, at spot: ParkingSpot? = nil, now: Date = Date()) async {
        guard let open = readSessionsOrReport() else { return }
        let targets = open.filter { s in
            belongs(s, to: car) && (spot == nil || s.spot?.id == spot?.id)
        }
        await finish(targets, now: now)
    }

    /// End every open session at `spot`, whoever it belongs to.
    func endAll(at spot: ParkingSpot, now: Date = Date()) async {
        guard let open = readSessionsOrReport() else { return }
        await finish(open.filter { $0.spot?.id == spot.id }, now: now)
    }

    func scheduleMoveAlert(for car: Car, at spot: ParkingSpot) async {
        await alerts.scheduleMoveAlert(for: car, at: spot)
    }

    func cancelMoveAlert(forCarID carID: UUID) async {
        await alerts.cancelMoveAlerts(forCarID: carID)
    }

    /// Next fire date of each car's pending "move your car" notification.
    static func pendingMoveAlertDates(forCarIDs carIDs: [UUID]) async -> [UUID: Date] {
        let alarms = await AlarmService.shared.allAlarms()
        var result: [UUID: Date] = [:]
        for id in carIDs {
            result[id] = alarms.filter { $0.carID == id }.map(\.endDate).min()
        }
        return result
    }

    // MARK: - Private

    private func openSessions() throws -> [ParkSession] {
        let descriptor = FetchDescriptor<ParkSession>(predicate: #Predicate { $0.endedAt == nil })
        return try context.fetch(descriptor)
    }

    private func readSessionsOrReport() -> [ParkSession]? {
        do { return try openSessions() }
        catch { AppIssueStore.shared.message = "Couldn’t read parking sessions: \(error.localizedDescription)"; return nil }
    }

    private func belongs(_ session: ParkSession, to car: Car?) -> Bool {
        if let car { return session.car?.id == car.id }
        return session.car == nil
    }

    private func finish(_ sessions: [ParkSession], now: Date) async {
        guard !sessions.isEmpty else { return }
        for s in sessions { s.endedAt = now }
        do { try context.save() } catch {
            context.rollback()
            AppIssueStore.shared.message = "Couldn't save parking: \(error.localizedDescription)"
            return
        }
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
        guard let open = readSessionsOrReport() else { return }
        let stillOccupied = Set(open.compactMap { $0.spot?.id })
        for (id, spot) in spots where id != keepingSpotID && !stillOccupied.contains(id) {
            await alerts.cancelSpotReminders(for: spot)
        }
    }
}

/// Live implementation backed by `NotificationManager`, `UNUserNotificationCenter` and `AlarmService`.
struct SystemParkingAlerts: ParkingAlerts {
    let context: ModelContext
    func scheduleSpotReminders(for spot: ParkingSpot) async {
        await ReminderCoordinator.shared.reconcile(context: context)
    }
    func cancelSpotReminders(for spot: ParkingSpot) async {
        await NotificationManager.shared.cancel(for: spot.restrictionsList, spot: spot)
        await ReminderCoordinator.shared.reconcile(context: context)
    }
    func scheduleMoveAlert(for car: Car, at spot: ParkingSpot) async {
        await ReminderCoordinator.shared.enable(context: context)
        await ReminderCoordinator.shared.resumeCancelled(context: context, carID: car.id)
    }
    func cancelMoveAlerts(forCarID carID: UUID) async {
        await ReminderCoordinator.shared.cancel(carID: carID)
        await AlarmService.shared.cancelAlarms(forCarID: carID)
    }
}
