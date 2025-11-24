// AlarmService.swift
import Foundation
import SwiftUI

#if canImport(AlarmKit)
import AlarmKit
#endif

/// A lightweight wrapper around AlarmKit to provide alarm scheduling and management with graceful fallback on iOS versions prior to 18.
/// 
/// - Note: On iOS versions earlier than 18 where AlarmKit is unavailable, all operations will either fail or return empty results.
/// - Limitations:
///   - Scheduling alarms is only supported on iOS 18+ with AlarmKit available.
///   - Authorization requests will always fail on unsupported versions.
///   - Listing and cancelling alarms are no-ops or return empty on unsupported versions.
@MainActor
final class AlarmService: ObservableObject {
    static let shared = AlarmService()
    private init() {}

    enum AlarmError: Error { case notSupported, notAuthorized }

    struct SimpleAlarm: Identifiable, Equatable {
        let id: UUID
        let title: String
        let endDate: Date
        #if canImport(AlarmKit)
        let raw: Alarm?
        #else
        let raw: Any?
        #endif
    }

    // MARK: - Authorization

    /// Request authorization to schedule and manage alarms.
    /// - Returns: true if authorized, false otherwise or if unsupported.
    func requestAuthorization() async -> Bool {
        #if canImport(AlarmKit)
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            return state == .authorized
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    // MARK: - Schedule

    /// Schedule a countdown alarm with a specified duration and optional title.
    ///
    /// - Parameters:
    ///   - seconds: Countdown duration in seconds.
    ///   - title: Title of the alarm (default is "Parking Timer").
    /// - Returns: A `SimpleAlarm` representing the scheduled alarm.
    /// - Throws: `AlarmError.notSupported` if AlarmKit is unavailable.
    func scheduleCountdown(seconds: TimeInterval, title: String = "Parking Timer") async throws -> SimpleAlarm {
        #if canImport(AlarmKit)
        let id = UUID()
        let countdown = Alarm.CountdownDuration(preAlert: seconds, postAlert: 0)

        let alert = AlarmPresentation.Alert(
            title: title,
            stopButton: .stopButton,
            secondaryButton: .snoozeButton,
            secondaryButtonBehavior: .countdown
        )
        let countdownUI = AlarmPresentation.Countdown(title: "Time Remaining", pauseButton: .pauseButton)
        let presentation = AlarmPresentation(alert: alert, countdown: countdownUI, paused: nil)

        struct EmptyMetadata: AlarmMetadata {}
        let attributes = AlarmAttributes(presentation: presentation, metadata: EmptyMetadata(), tintColor: .orange)

        let config = AlarmManager.AlarmConfiguration(countdownDuration: countdown, schedule: nil, attributes: attributes, sound: .default)
        let alarm = try await AlarmManager.shared.schedule(id: id, configuration: config)
        let endDate = Date().addingTimeInterval(seconds)
        return SimpleAlarm(id: id, title: title, endDate: endDate, raw: alarm)
        #else
        throw AlarmError.notSupported
        #endif
    }

    // MARK: - Query

    /// Retrieve all scheduled alarms.
    /// - Returns: An array of `SimpleAlarm` instances; empty if unsupported or on error.
    func allAlarms() async -> [SimpleAlarm] {
        #if canImport(AlarmKit)
        do {
            let alarms = try AlarmManager.shared.alarms
            return alarms.map { alarm in
                let endDate: Date
                if let cd = alarm.countdownDuration, let pre = cd.preAlert {
                    endDate = Date().addingTimeInterval(pre)
                } else {
                    endDate = Date()
                }
                return SimpleAlarm(id: alarm.id, title: alarm.attributes.presentation.alert.title ?? "Alarm", endDate: endDate, raw: alarm)
            }
        } catch {
            return []
        }
        #else
        return []
        #endif
    }

    // MARK: - Control

    /// Cancel a scheduled alarm by its identifier.
    /// - Parameter id: The UUID of the alarm to cancel.
    func cancel(id: UUID) async {
        #if canImport(AlarmKit)
        do { try await AlarmManager.shared.cancel(id: id) } catch { }
        #endif
    }
}
