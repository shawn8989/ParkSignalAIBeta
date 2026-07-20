import Foundation
import UserNotifications
import SwiftData

final class NotificationManager {

    static let shared = NotificationManager()
    private init() {}

    // Default lead time 15 minutes; user-editable via SettingsView (@AppStorage writes to UserDefaults)
    var leadMinutes: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: "alertLeadMinutes")
            return value == 0 ? 15 : value
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "alertLeadMinutes")
        }
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func schedule(for restrictions: [Restriction], spot: ParkingSpot) async {
        let allowed: Set<RestrictionType> = [.streetCleaning, .noParking]
        let center = UNUserNotificationCenter.current()
        let ok = await requestAuthorizationIfNeeded()
        guard ok else { return }

        for r in restrictions where allowed.contains(r.type) {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: r.startTime)
            let startHour = comps.hour ?? 0
            let startMinute = comps.minute ?? 0

            for dow in r.daysOfWeek {
                let lead = computeLead(weekday0_6: dow, startHour: startHour, startMinute: startMinute, leadMinutes: leadMinutes)
                var dateComps = DateComponents()
                dateComps.weekday = lead.weekday1_7
                dateComps.hour = lead.hour
                dateComps.minute = lead.minute

                let content = UNMutableNotificationContent()
                content.title = title(for: r)
                content.body = "Starts at \(formatTime(r.startTime)) near \(spot.location)"
                content.sound = .default
                if #available(iOS 15.0, *) {
                    content.interruptionLevel = .timeSensitive
                }

                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComps, repeats: true)
                let id = "restriction.\(r.id.uuidString).\(lead.weekday1_7)"
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                do {
                    NotificationLogStore.shared.appendScheduled(id: id, title: content.title, body: content.body, categoryIdentifier: content.categoryIdentifier.isEmpty ? nil : content.categoryIdentifier, scheduledFor: nil, userInfo: nil)
                    try await center.add(request)
                } catch {
                    // Best-effort; ignore individual failures
                }
            }
        }
    }

    /// Cancel any pending weekly notifications previously scheduled for the given restrictions at this spot.
    /// Uses the same identifier scheme as `schedule(for:spot:)` ("restriction.<restrictionID>.<weekday1_7>").
    /// We recompute the alert weekday using the same lead-time logic to derive exact identifiers to remove.
    func cancel(for restrictions: [Restriction], spot: ParkingSpot) async {
        let center = UNUserNotificationCenter.current()
        // Build the exact identifiers we used when scheduling.
        var ids: [String] = []
        for r in restrictions {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: r.startTime)
            let startHour = comps.hour ?? 0
            let startMinute = comps.minute ?? 0
            for dow in r.daysOfWeek {
                let lead = computeLead(weekday0_6: dow, startHour: startHour, startMinute: startMinute, leadMinutes: leadMinutes)
                let id = "restriction.\(r.id.uuidString).\(lead.weekday1_7)"
                ids.append(id)
            }
        }
        // Remove any matching pending requests. Best-effort; safe to call even if none exist.
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func title(for r: Restriction) -> String {
        switch r.type {
        case .streetCleaning: return "Street Cleaning Reminder"
        case .noParking: return "No Parking Reminder"
        default: return "Parking Reminder"
        }
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }

    // Compute pre-start alert time possibly on the previous weekday
    private func computeLead(weekday0_6: Int, startHour: Int, startMinute: Int, leadMinutes: Int) -> (weekday1_7: Int, hour: Int, minute: Int) {
        let startTotal = startHour * 60 + startMinute
        var alertTotal = startTotal - leadMinutes
        var weekday = weekday0_6
        if alertTotal < 0 {
            alertTotal += 24 * 60
            weekday = (weekday - 1 + 7) % 7
        }
        let hour = alertTotal / 60
        let minute = alertTotal % 60
        // Convert 0..6 (Sun..Sat) to 1..7 (Sun..Sat) for DateComponents.weekday
        let weekday1_7 = ((weekday + 1 - 1) % 7) + 1
        return (weekday1_7, hour, minute)
    }

    // Schedules a one-off test notification in `seconds` seconds
    func scheduleTestNotification(seconds: TimeInterval = 3) async {
        let center = UNUserNotificationCenter.current()
        let ok = await requestAuthorizationIfNeeded()
        guard ok else { return }
        let content = UNMutableNotificationContent()
        content.title = "Test Parking Reminder"
        content.body = "This is a test notification from Settings/Quick Scan."
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: "notification.test.oneoff", content: content, trigger: trigger)
        do {
            NotificationLogStore.shared.appendScheduled(id: request.identifier, title: content.title, body: content.body, categoryIdentifier: content.categoryIdentifier.isEmpty ? nil : content.categoryIdentifier, scheduledFor: Date().addingTimeInterval(seconds), userInfo: nil)
            try await center.add(request)
        } catch {
            // ignore in test
        }
    }
}

