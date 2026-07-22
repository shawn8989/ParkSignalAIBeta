// AlarmService.swift
import Foundation
import SwiftUI
import Combine
import UserNotifications

#if canImport(AlarmKit)
import AlarmKit
#endif

#if canImport(ActivityKit)
import ActivityKit
#endif

/// A lightweight wrapper around AlarmKit to provide alarm scheduling and management with graceful fallback on iOS versions prior to 26.
/// 
/// - Note: On iOS versions earlier than 26 where AlarmKit is unavailable, all operations will either fail or return empty results.
/// - Limitations:
///   - Scheduling alarms is only supported on iOS 26+ with AlarmKit available.
///   - Authorization requests will always fail on unsupported versions.
///   - Listing and cancelling alarms are no-ops or return empty on unsupported versions.
@MainActor
final class AlarmService: ObservableObject {
    static let shared = AlarmService()
    let objectWillChange = ObservableObjectPublisher()
    private init() {}
    
    private let authCacheKey = "AlarmService.AuthorizationCached"
    private func setCachedAuthorization(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: authCacheKey)
    }
    func isAuthorizedCached() -> Bool {
        return UserDefaults.standard.bool(forKey: authCacheKey)
    }

    private let metadataKey = "AlarmService.Metadata"

    private func loadMetadata() -> [String: [String: String]] {
        return UserDefaults.standard.dictionary(forKey: metadataKey) as? [String: [String: String]] ?? [:]
    }

    private func saveMetadata(_ dict: [String: [String: String]]) {
        UserDefaults.standard.set(dict, forKey: metadataKey)
    }

    private func saveMetadata(forAlarmID alarmID: UUID?, notificationIdentifier: String?, carID: UUID?, spotID: UUID?) {
        var dict = loadMetadata()
        var payload: [String: String] = [:]
        if let carID { payload["car"] = carID.uuidString }
        if let spotID { payload["spot"] = spotID.uuidString }
        if let alarmID { dict[alarmID.uuidString] = payload }
        if let notificationIdentifier { dict[notificationIdentifier] = payload }
        saveMetadata(dict)
    }

    private func metadata(forAlarmID alarmID: UUID) -> (car: UUID?, spot: UUID?) {
        let dict = loadMetadata()
        if let payload = dict[alarmID.uuidString] {
            let car = payload["car"].flatMap(UUID.init(uuidString:))
            let spot = payload["spot"].flatMap(UUID.init(uuidString:))
            return (car, spot)
        }
        return (nil, nil)
    }

    private func metadata(forNotificationIdentifier ident: String) -> (car: UUID?, spot: UUID?) {
        let dict = loadMetadata()
        if let payload = dict[ident] {
            let car = payload["car"].flatMap(UUID.init(uuidString:))
            let spot = payload["spot"].flatMap(UUID.init(uuidString:))
            return (car, spot)
        }
        return (nil, nil)
    }

    enum AlarmError: Error { case notSupported, notAuthorized }

    struct SimpleAlarm: Identifiable, Equatable {
        enum Source { case alarmKit, notification }
        static func == (lhs: AlarmService.SimpleAlarm, rhs: AlarmService.SimpleAlarm) -> Bool {
            return lhs.id == rhs.id && lhs.notificationIdentifier == rhs.notificationIdentifier
        }
        let id: UUID
        let title: String
        let endDate: Date
        let raw: Any?
        let source: Source
        let notificationIdentifier: String?
        let carID: UUID?
        let spotID: UUID?
    }

#if canImport(AlarmKit)
    struct EmptyMetadata: AlarmMetadata {}
#endif

    // MARK: - Authorization

    /// Request authorization to schedule and manage alarms.
    /// - Returns: true if authorized, false otherwise or if unsupported.
    func requestAuthorization() async -> Bool {
        #if canImport(AlarmKit)
        do {
            if #available(iOS 26.0, *) {
                let state = try await AlarmManager.shared.requestAuthorization()
                let ok = (state == .authorized)
                setCachedAuthorization(ok)
                return ok
            } else {
                setCachedAuthorization(false)
                return false
            }
        } catch {
            setCachedAuthorization(false)
            return false
        }
        #else
        setCachedAuthorization(false)
        return false
        #endif
    }

    // MARK: - Schedule

    /// Schedule a countdown alarm with a specified duration and optional title.
    ///
    /// - Parameters:
    ///   - seconds: Countdown duration in seconds.
    ///   - title: Title of the alarm (default is "Parking Timer").
    ///   - carID: Optional car identifier metadata.
    ///   - spotID: Optional spot identifier metadata.
    /// - Returns: A `SimpleAlarm` representing the scheduled alarm.
    /// - Throws: `AlarmError.notSupported` if AlarmKit is unavailable.
    func scheduleCountdown(seconds: TimeInterval, title: LocalizedStringResource = "Parking Timer", carID: UUID? = nil, spotID: UUID? = nil) async throws -> SimpleAlarm {
        #if canImport(AlarmKit)
        #if ALARMKIT_HAS_STANDARD_BUTTONS
        if #available(iOS 26.0, *) {
            let id = UUID()
            let countdown = Alarm.CountdownDuration(preAlert: seconds, postAlert: 0)

            let stopButton = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle")
            let repeatButton = AlarmButton(text: "Repeat", textColor: .white, systemImageName: "repeat.circle")
            let pauseButton = AlarmButton(text: "Pause", textColor: .white, systemImageName: "pause.circle")

            let alert = AlarmPresentation.Alert(
                title: title,
                stopButton: stopButton,
                secondaryButton: repeatButton,
                secondaryButtonBehavior: .countdown
            )
            let countdownUI = AlarmPresentation.Countdown(
                title: LocalizedStringResource("Time Remaining"),
                pauseButton: pauseButton
            )
            let presentation = AlarmPresentation(alert: alert, countdown: countdownUI, paused: nil)

            let attributes: AlarmAttributes<EmptyMetadata> = AlarmAttributes(presentation: presentation, metadata: EmptyMetadata(), tintColor: .orange)

            let config = AlarmManager.AlarmConfiguration(countdownDuration: countdown, schedule: nil, attributes: attributes, sound: .default)
            let alarm = try await AlarmManager.shared.schedule(id: id, configuration: config)
            self.objectWillChange.send()
            let endDate = Date().addingTimeInterval(seconds)
            // Save metadata for routing
            saveMetadata(forAlarmID: id, notificationIdentifier: nil, carID: carID, spotID: spotID)
            return SimpleAlarm(id: id, title: String(localized: title), endDate: endDate, raw: alarm, source: .alarmKit, notificationIdentifier: nil, carID: carID, spotID: spotID)
        } else {
            return await scheduleFallbackLocalNotification(seconds: seconds, title: String(localized: title), carID: carID, spotID: spotID)
        }
        #else
        return await scheduleFallbackLocalNotification(seconds: seconds, title: String(localized: title), carID: carID, spotID: spotID)
        #endif
        #else
        return await scheduleFallbackLocalNotification(seconds: seconds, title: String(localized: title), carID: carID, spotID: spotID)
        #endif
    }

    // MARK: - Query

    func allAlarms() async -> [SimpleAlarm] {
        var results: [SimpleAlarm] = []

        // AlarmKit alarms
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                let alarms = try AlarmManager.shared.alarms
                let mapped: [SimpleAlarm] = alarms.map { alarm in
                    let endDate: Date
                    if let cd = alarm.countdownDuration, let pre = cd.preAlert {
                        endDate = Date().addingTimeInterval(pre)
                    } else {
                        endDate = Date()
                    }
                    let meta = metadata(forAlarmID: alarm.id)
                    return SimpleAlarm(
                        id: alarm.id,
                        title: "Parking Alarm",
                        endDate: endDate,
                        raw: alarm,
                        source: .alarmKit,
                        notificationIdentifier: nil,
                        carID: meta.car,
                        spotID: meta.spot
                    )
                }
                results.append(contentsOf: mapped)
            } catch { }
        }
        #endif

        // Pending local notifications (fallback and restriction alerts)
        let reqs = await pendingNotificationRequests()
        for r in reqs {
            var endDate = Date()
            if let trig = r.trigger as? UNCalendarNotificationTrigger, let next = trig.nextTriggerDate() {
                endDate = next
            } else if let trig = r.trigger as? UNTimeIntervalNotificationTrigger {
                endDate = Date().addingTimeInterval(trig.timeInterval)
            }
            // Parse identifier for car/spot
            var parsedCar: UUID? = nil
            var parsedSpot: UUID? = nil
            let parts = r.identifier.split(separator: ".").map(String.init)
            if parts.count >= 4 {
                // pattern: nextRestriction car <uuid> spot <uuid>
                if let carIdx = parts.firstIndex(of: "car"), carIdx+1 < parts.count {
                    parsedCar = UUID(uuidString: parts[carIdx+1])
                }
                if let spotIdx = parts.firstIndex(of: "spot"), spotIdx+1 < parts.count {
                    parsedSpot = UUID(uuidString: parts[spotIdx+1])
                }
            }
            // Merge with metadata store
            let meta = metadata(forNotificationIdentifier: r.identifier)
            let carID = parsedCar ?? meta.car
            let spotID = parsedSpot ?? meta.spot

            let simple = SimpleAlarm(
                id: UUID(),
                title: r.content.title.isEmpty ? "Notification" : r.content.title,
                endDate: endDate,
                raw: nil,
                source: .notification,
                notificationIdentifier: r.identifier,
                carID: carID,
                spotID: spotID
            )
            results.append(simple)
        }
        results.sort { $0.endDate < $1.endDate }
        return results
    }

    // MARK: - Control

    /// Cancel a scheduled alarm by its identifier.
    /// - Parameter id: The UUID of the alarm to cancel.
    func cancel(id: UUID) async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                try await AlarmManager.shared.cancel(id: id)
                self.objectWillChange.send()
            } catch { }
        }
        #endif
    }

    func cancelNotification(identifier: String) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        self.objectWillChange.send()
    }

    /// Cancel all scheduled alarms — both AlarmKit alarms and pending local notifications.
    func cancelAll() async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                let alarms = try AlarmManager.shared.alarms
                for alarm in alarms {
                    try await AlarmManager.shared.cancel(id: alarm.id)
                }
                self.objectWillChange.send()
            } catch {
                // ignore failures
            }
        }
        #endif
        cancelAllFallbackNotifications()
    }

    /// Fallback: cancel all pending local notifications scheduled by the app.
    private func cancelAllFallbackNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
    }

    private func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { reqs in
                continuation.resume(returning: reqs)
            }
        }
    }

    // Fallback: schedule a local notification when AlarmKit isn't available
    private func scheduleFallbackLocalNotification(seconds: TimeInterval, title: String, carID: UUID?, spotID: UUID?) async -> SimpleAlarm {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Timer finished."
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        let uuid = UUID()
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: uuid.uuidString, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch { }
        let endDate = Date().addingTimeInterval(seconds)
        // Save metadata for routing
        saveMetadata(forAlarmID: uuid, notificationIdentifier: uuid.uuidString, carID: carID, spotID: spotID)
        return SimpleAlarm(id: uuid, title: title, endDate: endDate, raw: nil, source: .notification, notificationIdentifier: uuid.uuidString, carID: carID, spotID: spotID)
    }
}

