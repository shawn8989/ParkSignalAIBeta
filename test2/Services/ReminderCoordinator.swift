import Foundation
import SwiftData
import UserNotifications
import Combine

struct PlannedReminder: Codable, Equatable, Identifiable {
    let id: String
    let carID: UUID?
    let spotID: UUID
    let fireDate: Date
    let deadline: Date
    let title: String
    let body: String
    var fingerprint: String { "\(id)|\(carID?.uuidString ?? "")|\(spotID.uuidString)|\(fireDate.timeIntervalSince1970)|\(deadline.timeIntervalSince1970)|\(title)|\(body)" }
}

/// Saved rules produce a rolling fourteen-day schedule on this device. Opening
/// the app extends the horizon; individual fired/cancelled occurrences stay retired.
enum ReminderPlanner {
    static func plan(sessions: [ParkSession], leadMinutes: Int, now: Date, calendar: Calendar = .current) -> [PlannedReminder] {
        // Concurrent offline edits can temporarily sync two open sessions for a
        // car. Select the newest deterministically, without mutating cloud data.
        var newest: [String: ParkSession] = [:]
        for session in sessions.filter({ $0.endedAt == nil }).sorted(by: {
            $0.startedAt == $1.startedAt ? $0.id.uuidString > $1.id.uuidString : $0.startedAt > $1.startedAt
        }) {
            let key = session.car?.id.uuidString ?? "carless"
            if newest[key] == nil { newest[key] = session }
        }
        return newest.values.flatMap { session -> [PlannedReminder] in
            guard let spot = session.spot, !spot.signScansList.contains(where: \.needsReview),
                  !spot.restrictionsList.contains(where: { $0.needsReview || $0.type == .other }) else { return [] }
            var cal = calendar
            if let zone = TimeZone(identifier: spot.timeZoneIdentifier) { cal.timeZone = zone }
            let today = cal.startOfDay(for: now)
            let horizon = cal.date(byAdding: .day, value: 14, to: today) ?? now
            var deadlines = Set<Date>()
            for rule in spot.restrictionsList {
                let allDay = cal.component(.hour, from: rule.startTime) == cal.component(.hour, from: rule.endTime)
                    && cal.component(.minute, from: rule.startTime) == cal.component(.minute, from: rule.endTime)
                if allDay, rule.daysOfWeek.isEmpty || Set(rule.daysOfWeek).count == 7,
                   let duration = rule.durationMinutes, duration > 0,
                   rule.type != .noParking && rule.type != .streetCleaning {
                    // An unrestricted daily window does not reset a stay limit at
                    // midnight, including limits longer than one calendar day.
                    let deadline = session.startedAt.addingTimeInterval(Double(duration) * 60)
                    if deadline > now && deadline < horizon { deadlines.insert(deadline) }
                    continue
                }
                for offset in -1..<14 {
                    guard let day = cal.date(byAdding: .day, value: offset, to: today),
                          rule.daysOfWeek.isEmpty || rule.daysOfWeek.contains(cal.component(.weekday, from: day) - 1),
                          let start = cal.date(bySettingHour: cal.component(.hour, from: rule.startTime), minute: cal.component(.minute, from: rule.startTime), second: 0, of: day),
                          var end = cal.date(bySettingHour: cal.component(.hour, from: rule.endTime), minute: cal.component(.minute, from: rule.endTime), second: 0, of: day) else { continue }
                    if end <= start { end = cal.date(byAdding: .day, value: 1, to: end) ?? end }
                    if rule.type == .noParking || rule.type == .streetCleaning {
                        if start > now && start >= session.startedAt { deadlines.insert(start) }
                    } else if let duration = rule.durationMinutes, duration > 0, session.startedAt < end {
                        let arrival = max(start, session.startedAt)
                        let deadline = arrival.addingTimeInterval(TimeInterval(duration * 60))
                        if deadline <= end && deadline > now && deadline < horizon { deadlines.insert(deadline) }
                    }
                }
            }
            return deadlines.map { deadline in
                // Keep the intended fire date stable. A newly enabled reminder
                // inside its lead window fires promptly; a previously delivered
                // occurrence is never recreated by reconciliation.
                let fire = max(deadline.addingTimeInterval(-Double(max(0, leadMinutes) * 60)), session.startedAt.addingTimeInterval(2))
                return PlannedReminder(id: "parking.v1.\(session.id.uuidString).\(Int(deadline.timeIntervalSince1970))", carID: session.car?.id, spotID: spot.id,
                    fireDate: fire, deadline: deadline, title: session.car.map { "Check parking for \($0.nickname)" } ?? "Check your parking",
                    body: "A saved parking rule at \(spot.location) reaches its deadline soon. Check the posted signs.")
            }
        }.sorted { $0.fireDate < $1.fireDate }
    }
}

struct ReminderHandle: Codable, Equatable {
    var alarmID: UUID?
    var notificationID: String?
    var key: String { alarmID.map { "alarm:\($0)" } ?? "notification:\(notificationID ?? "")" }
}

@MainActor
protocol ReminderBackend {
    func pendingKeys() async throws -> Set<String>
    func schedule(_ plan: PlannedReminder) async throws -> ReminderHandle
    func cancel(_ handle: ReminderHandle) async throws
}

struct DeviceReminderBackend: ReminderBackend {
    func pendingKeys() async throws -> Set<String> {
        Set(try await AlarmService.shared.checkedAlarms().map {
            $0.source == .alarmKit ? "alarm:\($0.id)" : "notification:\($0.notificationIdentifier ?? "")"
        })
    }
    func schedule(_ plan: PlannedReminder) async throws -> ReminderHandle {
        if AlarmService.shared.isAuthorizedCached() {
            do {
                let alarm = try await AlarmService.shared.scheduleCountdown(seconds: max(1, plan.fireDate.timeIntervalSinceNow),
                    title: LocalizedStringResource("\(plan.title)"), carID: plan.carID, spotID: plan.spotID)
                return ReminderHandle(alarmID: alarm.source == .alarmKit ? alarm.id : nil,
                                      notificationID: alarm.notificationIdentifier)
            } catch { /* Fall back only if local notifications are authorized. */ }
        }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard [.authorized, .provisional, .ephemeral].contains(status) else { throw AlarmService.AlarmError.notAuthorized }
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["spotID": plan.spotID.uuidString, "carID": plan.carID?.uuidString ?? ""]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, plan.fireDate.timeIntervalSinceNow), repeats: false)
        try await center.add(UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger))
        NotificationLogStore.shared.appendScheduled(id: plan.id, title: plan.title, body: plan.body,
            categoryIdentifier: nil, scheduledFor: plan.fireDate, userInfo: nil)
        return ReminderHandle(notificationID: plan.id)
    }
    func cancel(_ handle: ReminderHandle) async throws {
        if let id = handle.alarmID { try await AlarmService.shared.cancelChecked(id: id) }
        if let id = handle.notificationID { await AlarmService.shared.cancelNotification(identifier: id) }
    }
}

@MainActor
final class ReminderCoordinator: ObservableObject {
    static let shared = ReminderCoordinator()
    static let enabledKey = "parkingRemindersEnabledOnDevice"
    @Published var statusMessage: String?
    private let defaults: UserDefaults
    private let backend: any ReminderBackend
    private var running = false
    private var runAgain = false
    private let recordsKey = "parking.v1.reminderRecords"

    struct Record: Codable {
        var plan: PlannedReminder
        var handle: ReminderHandle?
        var suppressed: Bool = false
    }
    init(defaults: UserDefaults = .standard, backend: (any ReminderBackend)? = nil) {
        self.defaults = defaults
        self.backend = backend ?? DeviceReminderBackend()
    }
    private var records: [String: Record] {
        get { defaults.data(forKey: recordsKey).flatMap { try? JSONDecoder().decode([String: Record].self, from: $0) } ?? [:] }
        set {
            if let data = try? JSONEncoder().encode(newValue), data != defaults.data(forKey: recordsKey) { defaults.set(data, forKey: recordsKey) }
        }
    }
    func enable(context: ModelContext) async {
        defaults.set(true, forKey: Self.enabledKey)
        _ = await NotificationManager.shared.requestAuthorizationIfNeeded()
        await reconcile(context: context)
    }
    func reconcile(context: ModelContext) async {
        if running { runAgain = true; return }
        running = true
        defer { running = false }
        repeat {
            runAgain = false
            do {
                if backend is DeviceReminderBackend && !defaults.bool(forKey: "parking.v1.remindersMigrated") {
                    // Retire old repeating reminders/countdowns once, including
                    // those created before the app tracked session ownership.
                    let known = Set(records.values.compactMap { $0.handle?.key })
                    for alarm in try await AlarmService.shared.checkedAlarms() {
                        let key = alarm.source == .alarmKit ? "alarm:\(alarm.id)" : "notification:\(alarm.notificationIdentifier ?? "")"
                        let oldID = alarm.notificationIdentifier ?? ""
                        if !known.contains(key) && (alarm.carID != nil || alarm.spotID != nil || oldID.hasPrefix("restriction.") || oldID.hasPrefix("nextRestriction.")) {
                            try await backend.cancel(ReminderHandle(alarmID: alarm.source == .alarmKit ? alarm.id : nil, notificationID: alarm.notificationIdentifier))
                        }
                    }
                    defaults.set(true, forKey: "parking.v1.remindersMigrated")
                }
                let sessions = try context.fetch(FetchDescriptor<ParkSession>())
                let plans = defaults.bool(forKey: Self.enabledKey)
                    ? ReminderPlanner.plan(sessions: sessions, leadMinutes: NotificationManager.shared.leadMinutes, now: Date()) : []
                try await apply(plans)
            } catch { statusMessage = "Reminders could not be updated. Check permissions and try again. \(error.localizedDescription)" }
        } while runAgain
    }
    /// Testable reconciliation: unchanged plans are idempotent; manual cancellation
    /// persists until the rule/session/lead time changes its fingerprint.
    func apply(_ plans: [PlannedReminder], now: Date = Date()) async throws {
        var saved = records
        defer { records = saved }
        let desired = Dictionary(plans.prefix(48).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pending = try await backend.pendingKeys()
        for (id, record) in saved where desired[id]?.fingerprint != record.plan.fingerprint {
            if let handle = record.handle { try await backend.cancel(handle) }
            saved.removeValue(forKey: id)
        }
        for (id, plan) in desired {
            if let current = saved[id] {
                if current.suppressed {
                    if let handle = current.handle, pending.contains(handle.key) { try await backend.cancel(handle) }
                    continue
                }
                if let handle = current.handle {
                    if pending.contains(handle.key) { continue }
                    if current.plan.fireDate <= now { continue } // Already fired or dismissed outside the app.
                }
            }
            let handle = try await backend.schedule(plan)
            saved[id] = Record(plan: plan, handle: handle)
        }
        statusMessage = plans.count > 48 ? "Only the next 48 parking reminders are scheduled on this device." : nil
    }
    func suppress(_ alarm: AlarmService.SimpleAlarm) {
        var saved = records
        for id in saved.keys where saved[id]?.handle?.alarmID == alarm.id || (alarm.notificationIdentifier != nil && saved[id]?.handle?.notificationID == alarm.notificationIdentifier) {
            saved[id]?.suppressed = true
        }
        records = saved
    }
    func resumeCancelled(context: ModelContext, carID: UUID? = nil) async {
        do { try await restoreCancelled(carID: carID) }
        catch {
            statusMessage = "A previous reminder could not be cleared. Try restoring again."
            return
        }
        await reconcile(context: context)
    }
    func restoreCancelled(carID: UUID? = nil) async throws {
        var saved = records
        defer { records = saved }
        for id in saved.keys where saved[id]?.suppressed == true && (carID == nil || saved[id]?.plan.carID == carID) {
            // Keep ownership until the OS confirms cancellation, even if a
            // previous cancel failed. Otherwise restoring could duplicate an alarm.
            if let handle = saved[id]?.handle { try await backend.cancel(handle) }
            saved.removeValue(forKey: id)
        }
    }
    func suppressAll() {
        var saved = records
        for id in saved.keys { saved[id]?.suppressed = true }
        records = saved
    }
    func cancel(carID: UUID) async {
        var saved = records
        defer { records = saved }
        for id in saved.keys where saved[id]?.plan.carID == carID {
            saved[id]?.suppressed = true
            do { if let handle = saved[id]?.handle { try await backend.cancel(handle) } }
            catch { statusMessage = "A reminder could not be cancelled. Reopen Alerts and try again." }
        }
    }
}
